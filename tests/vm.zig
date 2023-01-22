const std = @import("std");
const VirtualMachine = @import("vm").VirtualMachine;
const InterpretResult = @import("vm").InterpretResult;

const VM = VirtualMachine();

test "smoke test" {
    const allocator = std.testing.allocator;
    var vm = VM.init(allocator, true);
    defer vm.deinit();

    var file = try std.fs.cwd().openFile("./tests/data/18_types.lox", .{});
    defer file.close();

    const buffer_size = 2000;
    const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
    defer allocator.free(file_buffer);

    std.debug.print("buf: {s}\n---\n", .{file_buffer});

    var input = "!(5 - 4 > 3 * 2 == !nil);";

    var result = try vm.interpret(input);
    try std.testing.expectEqual(result, InterpretResult.ok);
}
