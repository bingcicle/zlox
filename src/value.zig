const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const growCapacity = @import("main.zig").growCapacity;

pub const Value = struct { data: f64 };

pub fn ValueArray() type {
    return struct {
        const Self = @This();

        count: usize = 0,
        capacity: usize = 0,
        values: []Value = &[_]Value{},
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.allocatedSlice());
            self.* = undefined;
        }

        fn growArray(self: *Self, new_capacity: usize) anyerror!void {
            const new_memory = try self.allocator.realloc(self.allocatedSlice(), new_capacity);
            self.values.ptr = new_memory.ptr;
            self.capacity = new_memory.len;
        }

        fn allocatedSlice(self: Self) []Value {
            return self.values.ptr[0..self.capacity];
        }

        pub fn write(self: *Self, value: Value) anyerror!void {
            if (self.capacity < self.count + 1) {
                var capacity = growCapacity(self.capacity) catch |err| {
                    _ = err;
                    return;
                };
                try self.growArray(capacity);
            }

            self.values.ptr[self.count] = value;
            self.count += 1;
        }
    };
}

test "writeValue" {
    {
        var values = ValueArray().init(testing.allocator);
        defer values.deinit();

        try std.testing.expect(values.capacity == 0);
        try std.testing.expect(values.count == 0);

        var value = Value{ .data = 4.20 };
        try values.write(value);

        try std.testing.expect(values.values.ptr[0].data == 4.20);
        try std.testing.expect(values.capacity == 8);
        try std.testing.expect(values.count == 1);
    }
}
