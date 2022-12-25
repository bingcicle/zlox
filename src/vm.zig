const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig").Chunk;
const Opcode = @import("opcode.zig").Opcode;
const ArrayList = std.ArrayList;

pub const InterpretResult = enum(u8) {
    interpret_ok = 0x0,
    interpret_compile_error = 0x1,
    interpret_runtime_error = 0x2,
};

pub const STACK_MAX: u8 = 255;

pub fn VirtualMachine() type {
    return struct {
        const Self = @This();

        const _chunk = Chunk();
        allocator: Allocator,
        chunk: _chunk,
        debug_trace_execution: bool = false,
        stack: ArrayList(Value),
        ip: [*]u8 = undefined,

        pub fn init(allocator: Allocator, debug_trace_execution: bool) Self {
            var stack = ArrayList(Value).initCapacity(allocator, STACK_MAX) catch ArrayList(Value).init(allocator);
            return Self{ .allocator = allocator, .chunk = _chunk.init(allocator), .debug_trace_execution = debug_trace_execution, .stack = stack };
        }

        fn read_byte(self: *Self) u8 {
            var byte = self.ip[0];
            self.ip += 1;
            return byte;
        }

        fn read_constant(self: *Self) Value {
            return self.chunk.constants.values.ptr[self.read_byte()];
        }

        pub fn interpret(self: *Self, chunk: anytype) !InterpretResult {
            self.chunk = chunk;
            self.ip = self.chunk.code.ptr;
            return try self.run();
        }

        pub fn run(self: *Self) !InterpretResult {
            while (true) {
                if (self.debug_trace_execution) {
                    std.debug.print("    ", .{});
                    for (self.stack.items) |v| {
                        std.debug.print("[ ", .{});
                        debug.printValue(v);
                        std.debug.print(" ]", .{});
                    }
                    std.debug.print("\n", .{});

                    var offset = @ptrToInt(self.ip) - @ptrToInt(self.chunk.code.ptr);
                    _ = debug.disassembleInstruction(self.chunk, offset);
                }

                var opcode = @intToEnum(Opcode, self.read_byte());

                switch (opcode) {
                    Opcode.op_return => {
                        debug.printValue(self.pop());
                        std.debug.print("\n", .{});
                        return InterpretResult.interpret_ok;
                    },
                    Opcode.op_constant => {
                        var constant = self.read_constant();
                        debug.printValue(constant);
                        _ = try self.push(constant);
                        continue;
                    },
                    Opcode.op_add, Opcode.op_subtract, Opcode.op_multiply, Opcode.op_divide => {
                        var b: f64 = self.pop().data;
                        var a: f64 = self.pop().data;
                        const value = try Opcode.handleBinaryOp(opcode, a, b);
                        _ = try self.push(value);
                        continue;
                    },
                    Opcode.op_negate => {
                        var value = self.pop();
                        value.data *= -1.0;
                        _ = try self.push(value);
                        continue;
                    },
                }

                self.ip.* += 1;
            }
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit();
            self.* = undefined;
        }

        pub fn push(self: *Self, value: Value) !void {
            try self.stack.append(value);
        }

        pub fn pop(self: *Self) Value {
            return self.stack.pop();
        }
    };
}

test "interpret" {
    {
        var chunk = Chunk().init(testing.allocator);
        var vm = VirtualMachine().init(testing.allocator, true);
        defer chunk.deinit();
        defer vm.deinit();

        var idx = try chunk.addConstant(Value{ .data = 1.2 });
        try chunk.writeChunk(@enumToInt(Opcode.op_constant), 123);
        try chunk.writeChunk(idx, 123);

        idx = try chunk.addConstant(Value{ .data = 3.4 });
        try chunk.writeChunk(@enumToInt(Opcode.op_constant), 123);
        try chunk.writeChunk(idx, 123);

        try chunk.writeChunk(@enumToInt(Opcode.op_add), 123);

        idx = try chunk.addConstant(Value{ .data = 5.6 });
        try chunk.writeChunk(@enumToInt(Opcode.op_constant), 123);
        try chunk.writeChunk(idx, 123);

        try chunk.writeChunk(@enumToInt(Opcode.op_divide), 123);

        try chunk.writeChunk(@enumToInt(Opcode.op_negate), 123);
        try chunk.writeChunk(@enumToInt(Opcode.op_return), 123);

        _ = try vm.interpret(chunk);
    }
}
