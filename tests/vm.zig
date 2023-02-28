const std = @import("std");
const VM = @import("vm").VirtualMachine;
const InterpretResult = @import("vm").InterpretResult;

fn runTest(allocator: std.mem.Allocator, file_name: []const u8) !void {
    var vm = try VM.init(allocator, true);
    var result = vm.runFile(file_name);
    try std.testing.expectEqual(result, InterpretResult.ok);
    vm.deinit();
}

test "smoke test" {
    const allocator = std.testing.allocator;
    var vm = try VM.init(allocator, true);
    defer vm.deinit();

    var result = vm.runFile("./tests/data/18_types.lox");
    try std.testing.expectEqual(result, InterpretResult.ok);
}

test "all" {
    const allocator = std.testing.allocator;

    try runTest(allocator, "./tests/data/18_types.lox");
    try runTest(allocator, "./tests/data/19_strings.lox");
}
