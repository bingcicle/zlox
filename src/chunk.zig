const Chunk = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const growCapacity = @import("main.zig").growCapacity;
const Opcode = @import("opcode").Opcode;

const Constants = ValueArray();

count: usize = 0,
capacity: usize = 0,
code: []u8 = &[_]u8{},
lines: []u8 = &[_]u8{},
constants: Constants,
allocator: Allocator,

pub fn init(allocator: Allocator) Chunk {
    return Chunk{ .allocator = allocator, .constants = Constants.init(allocator) };
}

pub fn writeChunk(chunk: *Chunk, byte: u8, line: u8) anyerror!void {
    if (chunk.capacity < chunk.count + 1) {
        var capacity = growCapacity(chunk.capacity) catch |err| {
            std.debug.print("Error: {}", .{err});
            return;
        };
        try chunk.growArray(capacity);
    }

    chunk.capacity = 8;
    chunk.code.ptr[chunk.count] = byte;
    chunk.lines.ptr[chunk.count] = line;
    chunk.count += 1;
}

fn growArray(self: *Chunk, new_capacity: usize) anyerror!void {
    const new_code_memory = try self.allocator.realloc(self.code.ptr[0..self.capacity], new_capacity);
    const new_lines_memory = try self.allocator.realloc(self.lines.ptr[0..self.capacity], new_capacity);
    self.code.ptr = new_code_memory.ptr;
    self.lines.ptr = new_lines_memory.ptr;
    self.capacity = new_code_memory.len;
}

pub fn allocatedSlice(self: Chunk) []u8 {
    return self.code.ptr[0..self.capacity];
}

pub fn addConstant(self: *Chunk, value: Value) anyerror!u8 {
    try self.constants.write(value);
    return @truncate(u8, self.constants.count - 1);
}

/// Release all allocated memory.
pub fn deinit(self: *Chunk) void {
    self.allocator.free(self.code.ptr[0..self.capacity]);
    self.allocator.free(self.lines.ptr[0..self.capacity]);
    self.constants.deinit();
    self.* = undefined;
}

test "writeChunk" {
    {
        var basicChunk = Chunk.init(testing.allocator);
        defer basicChunk.deinit();

        try std.testing.expect(basicChunk.capacity == 0);
        try std.testing.expect(basicChunk.count == 0);

        try basicChunk.writeChunk(@enumToInt(Opcode.op_return), 123);
        try std.testing.expect(basicChunk.capacity == 8);
        try std.testing.expect(basicChunk.count == 1);
        try std.testing.expect(@intToEnum(Opcode, basicChunk.code.ptr[0]) == Opcode.op_return);
    }
}

test "disassembleChunk" {
    {
        var basicChunk = Chunk.init(testing.allocator);
        defer basicChunk.deinit();

        try std.testing.expect(basicChunk.capacity == 0);
        try std.testing.expect(basicChunk.count == 0);

        var value = Value.newNumber(4.2);
        var idx = try basicChunk.addConstant(value);
        try basicChunk.writeChunk(@enumToInt(Opcode.op_constant), 123);
        try basicChunk.writeChunk(idx, 123);
        try basicChunk.writeChunk(@enumToInt(Opcode.op_return), 123);

        const writer = std.io.getStdOut().writer();
        try debug.disassembleChunk(&basicChunk, "test chunk", writer);
    }
}

test "addConstant" {
    {
        var basicChunk = Chunk.init(testing.allocator);
        defer basicChunk.deinit();

        try std.testing.expect(basicChunk.capacity == 0);
        try std.testing.expect(basicChunk.count == 0);

        var value = Value.newNumber(4.2);
        var result = try basicChunk.addConstant(value);
        try std.testing.expect(result == 0);
        result = try basicChunk.addConstant(value);
        try std.testing.expect(result == 1);
    }
}

test "writeChunk: constant" {
    {
        var basicChunk = Chunk.init(testing.allocator);
        defer basicChunk.deinit();

        try std.testing.expect(basicChunk.capacity == 0);
        try std.testing.expect(basicChunk.count == 0);
    }
}
