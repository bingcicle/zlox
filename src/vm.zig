const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const Opcode = @import("opcode.zig").Opcode;
const ArrayList = std.ArrayList;
const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");

const Compiler = @import("Compiler.zig");

pub const InterpretResult = enum(u8) {
    interpret_ok = 0x0,
    interpret_compile_error = 0x1,
    interpret_runtime_error = 0x2,
};

pub const STACK_MAX: u8 = 255;

pub fn VirtualMachine() type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        chunk: Chunk,
        debug_trace_execution: bool = false,
        stack: ArrayList(Value),
        ip: [*]u8 = undefined,

        pub fn init(allocator: Allocator, debug_trace_execution: bool) Self {
            var stack = ArrayList(Value).initCapacity(allocator, STACK_MAX) catch ArrayList(Value).init(allocator);
            return Self{
                .allocator = allocator,
                .chunk = undefined,
                .debug_trace_execution = debug_trace_execution,
                .stack = stack,
            };
        }

        fn read_byte(self: *Self) u8 {
            var byte = self.ip[0];
            self.ip += 1;
            return byte;
        }

        fn read_constant(self: *Self) Value {
            return self.chunk.constants.values.ptr[self.read_byte()];
        }

        pub fn interpret(self: *Self, source: []const u8) !InterpretResult {
            var scanner = Scanner.init(source);
            var chunk = Chunk.init(self.allocator);

            var parser = Parser{
                .current = null,
                .previous = null,
                .had_error = false,
                .panic_mode = false,
                .compiling_chunk = &chunk,
                .scanner = &scanner,
            };

            // compile() returns false if an error occurred.
            var compiler = Compiler{};
            var had_error = try compiler.compile(&parser);

            if (!had_error) {
                return InterpretResult.interpret_compile_error;
            }

            self.chunk = chunk;
            self.ip = chunk.code.ptr;

            var result: InterpretResult = try self.run();

            return result;
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
                        return InterpretResult.interpret_ok;
                    },
                    Opcode.op_constant => {
                        var constant = self.read_constant();
                        _ = try self.push(constant);
                        continue;
                    },
                    Opcode.op_nil => {
                        _ = try self.push(Value.newNil());
                        continue;
                    },
                    Opcode.op_true => {
                        _ = try self.push(Value.newBool(true));
                        continue;
                    },
                    Opcode.op_false => {
                        _ = try self.push(Value.newBool(false));
                        continue;
                    },
                    Opcode.op_add, Opcode.op_subtract, Opcode.op_multiply, Opcode.op_divide => {
                        var b: f64 = Value.asNumber(self.pop());
                        var a: f64 = Value.asNumber(self.pop());
                        const value = try Opcode.handleBinaryOp(opcode, a, b);
                        _ = try self.push(value);
                        continue;
                    },
                    Opcode.op_negate => {
                        var value = self.pop();
                        value.data.number *= -1.0;
                        _ = try self.push(value);
                        continue;
                    },
                }

                self.ip.* += 1;
            }
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit();
            self.chunk.deinit();
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
