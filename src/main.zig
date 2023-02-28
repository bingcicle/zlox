const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const vm = @import("vm.zig");

const VM = vm.VirtualMachine;
const InterpretResult = vm.InterpretResult;

pub fn growCapacity(capacity: usize) anyerror!usize {
    switch (capacity < 8) {
        true => return 8,
        false => return (capacity * 2),
    }
}

fn repl(self: *VM, stdin: std.fs.File.Reader, stdout: std.fs.File.Writer) !void {
    repl: while (true) {
        const max_input = 1024;
        try stdout.print("\n> ", .{});
        var input_buffer: [max_input]u8 = undefined;
        var input = (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) orelse {
            try stdout.print("\n>", .{});
            return;
        };

        var result = try self.interpret(input);
        if (result == InterpretResult.ok) {
            break :repl;
        }
    }
}

pub fn main() anyerror!void {
    var arg_iter = std.process.args();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer {
        std.log.info("\n----\nUsed {} of memory.", .{std.fmt.fmtIntSizeDec(gpa.total_requested_bytes)});
        _ = gpa.deinit();
    }
    var allocator = gpa.allocator();

    var _vm = VM.init(allocator, false);
    defer _vm.deinit();

    if (arg_iter.inner.count == 1) {
        try repl(&_vm, stdin, stdout);
    } else if (arg_iter.inner.count == 2) {
        _ = arg_iter.next();
        _ = try _vm.runFile(arg_iter.next().?);
    }
}
