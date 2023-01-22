const std = @import("std");
const VM = @import("vm").VirtualMachine;
const InterpretResult = @import("vm").InterpretResult;
const runFile = @import("main").runFile;

test "smoke test" {
    const allocator = std.testing.allocator;
    var vm = VM.init(allocator, true);
    defer vm.deinit();

    var result = runFile(&vm, "./tests/data/18_types.lox");
    try std.testing.expectEqual(result, InterpretResult.ok);
}
