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
const ObjString = @import("Object.zig").ObjString;
const Obj = @import("Object.zig");
const Table = @import("Table.zig");
const builtin = @import("builtin");
const Local = @import("Compiler.zig").Local;

fn erase(ptr: anytype) void {
    const T = @TypeOf(ptr);
    const info = @typeInfo(T);
    if (info != .Pointer) @compileError("erase() wants pointer to local variable to erase; given non-pointer");
    if (info.Pointer.size != .One) @compileError("erase() wants *T; given " ++ @typeName(T));

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        const byte_ptr = @ptrCast([*]u8, @alignCast(1, ptr));
        @memset(byte_ptr, 0xaa, @sizeOf(info.Pointer.child));
    }
}

pub const VirtualMachine = @This();

pub const InterpretResult = enum(u8) {
    ok,
    compile_error,
    runtime_error,
};

const RuntimeError = error{
    OperandNotNumber,
    OperandsNotNumbers,
    UndefinedVariable,
};

pub const STACK_MAX: u8 = 255;

const Self = @This();

allocator: Allocator,
chunk: Chunk,
compiler: Compiler,
objects: ?*Obj,
globals: Table,
strings: Table,
debug_trace_execution: bool = false,
stack: ArrayList(Value),
ip: [*]u8 = undefined,

pub fn init(allocator: Allocator, debug_trace_execution: bool) !Self {
    var stack = ArrayList(Value).initCapacity(allocator, STACK_MAX) catch ArrayList(Value).init(allocator);
    return Self{
        .allocator = allocator,
        .chunk = undefined,
        .globals = try Table.init(allocator),
        .strings = try Table.init(allocator),
        .objects = null,
        .compiler = undefined,
        .debug_trace_execution = debug_trace_execution,
        .stack = stack,
    };
}

fn readFile(buffer: []u8, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    _ = try file.read(buffer);
}

pub fn runFile(self: *Self, path: []const u8) !InterpretResult {
    const max_input = 1024;
    var buf: [max_input]u8 = undefined;
    try readFile(
        &buf,
        path,
    );
    return try self.interpret(&buf);
}

fn readByte(self: *Self) u8 {
    var byte = self.ip[0];
    self.ip += 1;
    return byte;
}

fn readShort(self: *Self) u16 {
    var first_byte = @as(u16, @as(u16, self.ip[0]) << 8);
    var second_byte = @as(u16, self.ip[1]);
    self.ip += 2;
    return first_byte | second_byte;
}

fn readConstant(self: *Self) Value {
    return self.chunk.constants.values.ptr[self.readByte()];
}

fn readString(self: *Self) *Obj.ObjString {
    return Value.asString(self.readConstant());
}

pub fn interpret(self: *Self, source: []const u8) !InterpretResult {
    var scanner = Scanner.init(source);
    self.chunk = Chunk.init(self.allocator);

    var parser = Parser{
        .current = null,
        .previous = null,
        .had_error = false,
        .panic_mode = false,
        .scanner = &scanner,
    };

    // compile() returns false if an error occurred.
    self.compiler = Compiler.init(&parser, &self.chunk, self);
    std.debug.print("\n", .{});

    var had_error = try self.compiler.compile();

    if (!had_error) {
        return InterpretResult.compile_error;
    }

    self.ip = self.chunk.code.ptr;

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

        var opcode = @intToEnum(Opcode, self.readByte());

        switch (opcode) {
            Opcode.op_constant => {
                var constant = self.readConstant();
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
            Opcode.op_pop => {
                _ = self.pop();
                continue;
            },
            Opcode.op_get_local => {
                var slot = self.readByte();
                try self.push(self.stack.items[slot]);
                continue;
            },
            Opcode.op_set_local => {
                var slot = self.readByte();
                try self.stack.insert(slot, self.peek(0).?);
                continue;
            },
            Opcode.op_get_global => {
                var name = self.readString();

                var value: Value = undefined;
                if (!self.globals.get(name, &value)) {
                    _ = try self.runtimeError(RuntimeError.UndefinedVariable, name.chars);
                    return InterpretResult.runtime_error;
                }

                try self.push(value);
                continue;
            },
            Opcode.op_define_global => {
                var name = self.readString();
                _ = try self.globals.set(name, self.peek(0).?);
                _ = self.pop();
                continue;
            },
            Opcode.op_set_global => {
                var name = self.readString();
                if (try self.globals.set(name, self.peek(0).?)) {
                    _ = self.globals.delete(name);
                    _ = try self.runtimeError(RuntimeError.UndefinedVariable, name.chars);
                    return InterpretResult.runtime_error;
                }
                continue;
            },
            Opcode.op_equal => {
                var b = self.pop();
                var a = self.pop();
                _ = try self.push(Value.newBool(Value.equals(a, b)));
                continue;
            },
            Opcode.op_add => {
                if (self.peek(0)) |safe_peek| {
                    if (self.peek(1)) |safe_peek_inner| {
                        if (Value.isString(safe_peek) and Value.isString(safe_peek_inner)) {
                            const chars = try self.concatenate();
                            var hash = ObjString.hash(chars);
                            const obj_string = try ObjString.create(self, self.allocator, chars, hash);
                            _ = try self.push(Value.newObj(&obj_string.obj));
                            continue;
                        } else if (Value.isNumber(safe_peek) and Value.isNumber(safe_peek_inner)) {
                            var b: f64 = Value.asNumber(self.pop());
                            var a: f64 = Value.asNumber(self.pop());
                            const value = try Opcode.handleBinaryOp(opcode, a, b);
                            _ = try self.push(value);
                            continue;
                        } else {
                            try self.runtimeError(RuntimeError.OperandsNotNumbers, "");
                            return InterpretResult.runtime_error;
                        }
                    }
                }
                continue;
            },
            Opcode.op_subtract,
            Opcode.op_multiply,
            Opcode.op_divide,
            Opcode.op_greater,
            Opcode.op_less,
            => {
                if (self.peek(0)) |safe_peek| {
                    if (self.peek(1)) |safe_peek_inner| {
                        if (!Value.isNumber(safe_peek) or !Value.isNumber(safe_peek_inner)) {
                            try self.runtimeError(RuntimeError.OperandsNotNumbers, "");
                            return InterpretResult.runtime_error;
                        }
                    }
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
                        _ = try self.runtimeError(RuntimeError.OperandNotNumber, "");
                        return InterpretResult.runtime_error;
                    }
                    _ = try self.push(Value.newNumber(-Value.asNumber(self.pop())));
                }
                continue;
            },
            Opcode.op_print => {
                debug.printValue(self.pop());
                std.debug.print("\n", .{});
                continue;
            },
            Opcode.op_jump => {
                var offset = self.readShort();
                self.ip += offset;
                continue;
            },
            Opcode.op_jump_if_false => {
                var offset = self.readShort();

                if (Value.isFalsey(self.peek(0).?)) self.ip += offset;
                continue;
            },
            Opcode.op_loop => {
                var offset = self.readShort();
                self.ip -= offset;
                continue;
            },
            Opcode.op_return => {
                // Exit interpreter.
                return InterpretResult.ok;
            },
        }
        self.ip.* += 1;
    }
}

pub fn deinit(self: *Self) void {
    self.freeTable(&self.globals);
    self.freeTable(&self.strings);
    self.compiler.deinit();
    self.chunk.deinit();
    self.stack.deinit();
    self.freeObjects();
    self.* = undefined;
}

fn freeObjects(self: *Self) void {
    var object = self.objects;
    while (object != null) {
        var next = object.?.next;
        if (object) |safe_object| {
            safe_object.deinit(self.allocator);
            object = next;
        }
    }
}

fn freeTable(_: *Self, table: *Table) void {
    table.deinit();
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

pub fn concatenate(self: *Self) ![]const u8 {
    var b = Value.asString(self.pop());
    var a = Value.asString(self.pop());

    const chars = try self.allocator.alloc(u8, a.chars.len + b.chars.len);

    std.mem.copy(u8, chars[0..a.chars.len], a.chars);
    std.mem.copy(u8, chars[a.chars.len..], b.chars);

    return chars;
}

// Here we use anytype in place of a variadic function, which is C-style.
pub fn runtimeError(self: *Self, runtime_error: RuntimeError, args: []const u8) !void {
    var instruction = @ptrToInt(self.ip) - @ptrToInt(self.chunk.code.ptr) - 1;
    var line = self.chunk.lines.ptr[instruction];

    const stderr = std.io.getStdErr().writer();
    try stderr.print("[line {d}] in script: ", .{line});

    switch (runtime_error) {
        RuntimeError.OperandNotNumber => try stderr.print("Operand must be a number", .{}),
        RuntimeError.OperandsNotNumbers => try stderr.print("Operands must be numbers", .{}),
        RuntimeError.UndefinedVariable => try stderr.print("Undefined variable '{s}'.", .{args}),
    }
    try stderr.print("\n\n", .{});
}
