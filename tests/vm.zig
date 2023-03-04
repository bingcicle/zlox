const std = @import("std");
const VM = @import("vm").VirtualMachine;
const InterpretResult = @import("vm").InterpretResult;

fn runTest(file_name: []const u8) !void {
    const allocator = std.testing.allocator;
    var vm = try VM.init(allocator, true);
    defer vm.deinit();

    var result = try vm.runFile(file_name);

    try std.testing.expectEqual(InterpretResult.ok, result);
}

test "smoke test" {
    // try runTest("./tests/data/22_scope.lox");
}

test "all" {
    try runTest("./tests/data/18_types.lox");
    try runTest("./tests/data/19_strings.lox");
    try runTest("./tests/data/21_global_variables.lox");
    try runTest("./tests/data/22_scope.lox");
}
