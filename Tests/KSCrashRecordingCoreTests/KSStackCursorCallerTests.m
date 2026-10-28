#import <XCTest/XCTest.h>
#import "KSBinaryImageCache.h"
#import "KSCPU.h"
#import "KSDynamicLinker.h"
#import "KSMachineContext_Apple.h"
#import "Unwind/KSDwarfUnwind.h"
#import "Unwind/KSStackCursor_Unwind.h"

#if defined(__arm64__)
extern void ks_unwind_test_leaf(void);
extern void ks_unwind_test_framed(void);
extern void ks_unwind_test_dwarf_leaf(void);
extern void ks_unwind_test_dwarf_framed(void);
#endif

@interface KSStackCursorCallerTests : XCTestCase
@end

@implementation KSStackCursorCallerTests
#if defined(__arm64__)
- (void)testInterruptedFrameDoesNotLoseSavedCallerWhenPCEqualsLR
{
    struct Frame {
        uintptr_t previous;
        uintptr_t address;
    } frames[2];
    frames[0].previous = (uintptr_t)&frames[1];
    frames[0].address = 0x100002000;
    frames[1].previous = 0;
    frames[1].address = 0x100003000;
    KSMachineContext context = { 0 };
    arm_thread_state64_set_pc_fptr(context.machineContext.__ss, (void (*)(void))0x100001000);
    arm_thread_state64_set_lr_fptr(context.machineContext.__ss, (void (*)(void))0x100001000);
    arm_thread_state64_set_fp(context.machineContext.__ss, (uintptr_t)&frames[0]);
    arm_thread_state64_set_sp(context.machineContext.__ss, (uintptr_t)&frames[0] - 16);
    KSUnwindMethod method = KSUnwindMethod_FramePointer;
    KSStackCursor cursor;
    kssc_initWithUnwindMethods(&cursor, 10, &context, &method, 1);
    uintptr_t expected[] = { 0x100001000, 0x100002000, 0x100003000 };
    for (int pass = 0; pass < 2; pass++) {
        for (int index = 0; index < 3; index++) {
            XCTAssertTrue(cursor.advanceCursor(&cursor));
            XCTAssertEqual(cursor.stackEntry.address, expected[index]);
        }
        XCTAssertFalse(cursor.advanceCursor(&cursor));
        cursor.resetCursor(&cursor);
    }
}
- (void)testCompactUnwindUsesTheSavedCallerInsteadOfAStaleLinkRegister
{
    uintptr_t frame[] = { 0, 0x100002000 };
    KSMachineContext context = { 0 };
    uintptr_t pc = (uintptr_t)&ks_unwind_test_framed + 8;
    arm_thread_state64_set_pc_fptr(context.machineContext.__ss, (void (*)(void))pc);
    arm_thread_state64_set_lr_fptr(context.machineContext.__ss, (void (*)(void))(pc + 4));
    arm_thread_state64_set_fp(context.machineContext.__ss, (uintptr_t)frame);
    arm_thread_state64_set_sp(context.machineContext.__ss, (uintptr_t)frame);
    [self assertCaller:0x100002000 context:&context method:KSUnwindMethod_CompactUnwind];
}

- (void)testCompactUnwindPreservesTheLinkRegisterForAFramelessLeaf
{
    KSMachineContext context = { 0 };
    arm_thread_state64_set_pc_fptr(context.machineContext.__ss, ks_unwind_test_leaf);
    arm_thread_state64_set_lr_fptr(context.machineContext.__ss, (void (*)(void))0x100002000);
    arm_thread_state64_set_sp(context.machineContext.__ss, (uintptr_t)&context);
    [self assertCaller:0x100002000 context:&context method:KSUnwindMethod_CompactUnwind];
}

- (void)testDwarfUnwindUsesTheSavedCallerInsteadOfAStaleLinkRegister
{
    uintptr_t frame[] = { 0, 0x100002000 };
    KSMachineContext context = { 0 };
    uintptr_t pc = (uintptr_t)&ks_unwind_test_dwarf_framed + 8;
    arm_thread_state64_set_pc_fptr(context.machineContext.__ss, (void (*)(void))pc);
    arm_thread_state64_set_lr_fptr(context.machineContext.__ss, (void (*)(void))(pc + 4));
    arm_thread_state64_set_fp(context.machineContext.__ss, (uintptr_t)frame);
    arm_thread_state64_set_sp(context.machineContext.__ss, (uintptr_t)frame);
    [self assertCaller:0x100002000 context:&context method:KSUnwindMethod_Dwarf];
}

- (void)testDwarfUnwindPreservesTheLinkRegisterForAFramelessLeaf
{
    KSMachineContext context = { 0 };
    arm_thread_state64_set_pc_fptr(context.machineContext.__ss, ks_unwind_test_dwarf_leaf);
    arm_thread_state64_set_lr_fptr(context.machineContext.__ss, (void (*)(void))0x100002000);
    arm_thread_state64_set_sp(context.machineContext.__ss, (uintptr_t)&context);
    [self assertCaller:0x100002000 context:&context method:KSUnwindMethod_Dwarf];
    arm_thread_state64_set_fp(context.machineContext.__ss, 0x100004000);
    [self assertCaller:0x100002000 context:&context method:KSUnwindMethod_Dwarf];
}

- (void)testDwarfDoesNotRecoverAnUndefinedReturnRegister
{
    ksdl_init();
    uintptr_t pc = (uintptr_t)&ks_unwind_test_dwarf_framed;
    KSBinaryImageUnwindInfo info;
    XCTAssertTrue(ksbic_getUnwindInfoForAddress(pc, &info));
    XCTAssertTrue(info.hasEhFrame);
    KSDwarfUnwindResult result;
    XCTAssertFalse(ksdwarf_unwind(info.ehFrame, info.ehFrameSize, pc, (uintptr_t)&info, 0, 0x100002000,
                                  (uintptr_t)info.header, &result));
}

- (void)assertCaller:(uintptr_t)caller context:(KSMachineContext *)context method:(KSUnwindMethod)method
{
    ksdl_init();
    if (method == KSUnwindMethod_Dwarf) {
        KSBinaryImageUnwindInfo info;
        uintptr_t pc = kscpu_instructionAddress(context);
        XCTAssertTrue(ksbic_getUnwindInfoForAddress(pc, &info));
        XCTAssertTrue(info.hasEhFrame);
        const uint8_t *fde = NULL, *cie = NULL;
        size_t fdeSize = 0, cieSize = 0;
        bool wide = false;
        XCTAssertTrue(ksdwarf_findFDE(info.ehFrame, info.ehFrameSize, pc, (uintptr_t)info.header, &fde, &fdeSize, &cie,
                                      &cieSize, &wide));
        if (fde && cie) {
            KSDwarfCFIRow row;
            XCTAssertTrue(ksdwarf_buildCFIRow(cie, cieSize, fde, fdeSize, pc, wide, &row));
            XCTAssertEqual(row.registers[30].type,
                           pc == (uintptr_t)&ks_unwind_test_dwarf_leaf ? KSDwarfRuleSameValue : KSDwarfRuleOffset);
            KSDwarfUnwindResult result;
            XCTAssertTrue(ksdwarf_unwind(info.ehFrame, info.ehFrameSize, pc, kscpu_stackPointer(context),
                                         kscpu_framePointer(context), kscpu_linkRegister(context),
                                         (uintptr_t)info.header, &result));
            XCTAssertEqual(result.returnAddress, caller);
            if (pc == (uintptr_t)&ks_unwind_test_dwarf_leaf) {
                XCTAssertFalse(result.framePointerRestored);
                XCTAssertEqual(result.framePointer, kscpu_framePointer(context));
                const uint8_t *boundaryFDE = NULL, *boundaryCIE = NULL;
                size_t boundarySize = 0, boundaryCIESize = 0;
                XCTAssertTrue(ksdwarf_findFDE(info.ehFrame, info.ehFrameSize, pc + 3, (uintptr_t)info.header,
                                              &boundaryFDE, &boundarySize, &boundaryCIE, &boundaryCIESize, &wide));
                XCTAssertEqual(boundaryFDE, fde);
                XCTAssertTrue(ksdwarf_findFDE(info.ehFrame, info.ehFrameSize, pc + 4, (uintptr_t)info.header,
                                              &boundaryFDE, &boundarySize, &boundaryCIE, &boundaryCIESize, &wide));
                XCTAssertNotEqual(boundaryFDE, fde);
            }
        }
    }
    KSStackCursor cursor;
    kssc_initWithUnwindMethods(&cursor, 10, context, &method, 1);
    for (int pass = 0; pass < 2; pass++) {
        XCTAssertTrue(cursor.advanceCursor(&cursor));
        XCTAssertTrue(cursor.advanceCursor(&cursor));
        XCTAssertEqual(cursor.stackEntry.address, caller);
        XCTAssertEqual(kssc_getUnwindMethod(&cursor), method);
        cursor.resetCursor(&cursor);
    }
}

#endif
@end
