const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const VirtualMachine = @import("vm.zig").VirtualMachine;
const InterpretResult = @import("vm.zig").InterpretResult;

const VM = VirtualMachine();

pub fn growCapacity(capacity: usize) anyerror!usize {
    switch (capacity < 8) {
        true => return 8,
        false => return (capacity * 2),
    }
}

fn repl(vm: *VM, stdin: std.fs.File.Reader, stdout: std.fs.File.Writer) !void {
    repl: while (true) {
        const max_input = 1024;
        var input_buffer: [max_input]u8 = undefined;
        var input = (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) orelse {
            try stdout.print("\n", .{});
            return;
        };

        var result = try vm.interpret(input);
        if (result == InterpretResult.ok) {
            break :repl;
        }
    }
}

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer {
        std.log.info("\n----\nUsed {} of memory.", .{std.fmt.fmtIntSizeDec(gpa.total_requested_bytes)});
        _ = gpa.deinit();
    }
    var allocator = gpa.allocator();

    var vm = VM.init(allocator, true);
    defer vm.deinit();

    try repl(&vm, stdin, stdout);
}

test "smoke test" {
    const allocator = std.testing.allocator;
    var vm = VM.init(allocator, false);
    defer vm.deinit();
    var input = "!(5 - 4 > 3 * 2 == !nil);";

    var result = try vm.interpret(input);
    try std.testing.expectEqual(result, InterpretResult.ok);
}
