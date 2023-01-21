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
    ok,
    compile_error,
    runtime_error,
};

const RuntimeError = error{
    OperandNotNumber,
    OperandsNotNumbers,
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
                .scanner = &scanner,
            };

            // compile() returns false if an error occurred.
            var compiler = Compiler{
                .parser = &parser,
                .compiling_chunk = &chunk,
            };
            var had_error = try compiler.compile();

            if (!had_error) {
                return InterpretResult.compile_error;
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
                        return InterpretResult.ok;
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
                    Opcode.op_equal => {
                        var b = self.pop();
                        var a = self.pop();
                        _ = try self.push(Value.newBool(Value.equals(a, b)));
                        continue;
                    },
                    Opcode.op_add,
                    Opcode.op_subtract,
                    Opcode.op_multiply,
                    Opcode.op_divide,
                    Opcode.op_greater,
                    Opcode.op_less,
                    => {
                        if (self.peek(0)) |safe_peek| {
                            if (self.peek(1)) |safe_peek_inner| {
                                if (!Value.isNumber(safe_peek) or !Value.isNumber(safe_peek_inner)) {
                                    try self.runtimeError(RuntimeError.OperandsNotNumbers, .{});
                                    return InterpretResult.runtime_error;
                                }
                            } else {
                                continue;
                            }
                        } else {
                            continue;
                        }
                        var b: f64 = Value.asNumber(self.pop());
                        var a: f64 = Value.asNumber(self.pop());
                        const value = try Opcode.handleBinaryOp(opcode, a, b);
                        _ = try self.push(value);
                        continue;
                    },
                    Opcode.op_not => {
                        _ = try self.push(Value.newBool(Value.isFalsey(self.pop())));
                        continue;
                    },
                    Opcode.op_negate => {
                        if (self.peek(0)) |safe_peek| {
                            if (!Value.isNumber(safe_peek)) {
                                _ = try self.runtimeError(RuntimeError.OperandNotNumber, .{});
                                return InterpretResult.runtime_error;
                            }
                            _ = try self.push(Value.newNumber(-Value.asNumber(self.pop())));
                        }
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

        pub fn peek(self: *Self, distance: usize) ?Value {
            return if (self.stack.items.len > 0) self.stack.items[self.stack.items.len - 1 - distance] else null;
        }

        pub fn pop(self: *Self) Value {
            return self.stack.pop();
        }

        // Here we use anytype in place of a variadic function, which is C-style.
        pub fn runtimeError(self: *Self, runtime_error: RuntimeError, _: anytype) !void {
            var instruction = @ptrToInt(self.ip) - @ptrToInt(self.chunk.code.ptr) - 1;
            var line = self.chunk.lines.ptr[instruction];

            const stderr = std.io.getStdErr().writer();
            try stderr.print("[line {d}] in script: ", .{line});

            switch (runtime_error) {
                RuntimeError.OperandNotNumber => try stderr.print("Operand must be a number", .{}),
                RuntimeError.OperandsNotNumbers => try stderr.print("Operands must be numbers", .{}),
            }
            try stderr.print("\n\n", .{});
        }
    };
}
