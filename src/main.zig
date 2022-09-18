const std = @import("std");
const Allocator = std.mem.Allocator;

const Opcode = enum { op_return };

pub fn Chunk() type {
    return struct {
        const Self = @This();

        count: i16,
        capacity: i16,
        code: []u8,

        pub fn init() Self {
            return Self{ .count = 0, .capacity = 0, .code = &[_]u8{} };
        }
    };
}

fn growCapacity(capacity: i16) i16 {
    switch (capacity < 8) {
        true => 8,
        false => (capacity * 2),
    }
}

fn growArray(capacity: i16) i16 {
    switch (capacity < 8) {
        true => 8,
        false => (capacity * 2),
    }
}

pub fn writeChunk(chunk: *Chunk, byte: u8) void {
    if (chunk.capacity < chunk.count + 1) {
        var old_capacity = chunk.capacity;
        chunk.capacity = growCapacity(old_capacity);
        chunk.code = growArray();
    }

    chunk.code[chunk.count] = byte;
    chunk.count += 1;
}

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test "basicChunk" {
    {
        var basicChunk = Chunk().init();
        try std.testing.expect(basicChunk.capacity == 0);
        try std.testing.expect(basicChunk.count == 0);
    }
}
