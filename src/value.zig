const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const growCapacity = @import("main.zig").growCapacity;

pub const Value = struct {
    type: Type,
    data: ValueTypeTag,

    pub const Type = enum { bool, nil, number };

    pub fn newBool(value: bool) Value {
        return Value{ .type = Value.Type.bool, .data = ValueTypeTag{ .bool = value } };
    }

    pub fn newNil() Value {
        return Value{ .type = Value.Type.nil, .data = ValueTypeTag{ .number = 0 } };
    }

    pub fn newNumber(value: f64) Value {
        return Value{ .type = Value.Type.number, .data = ValueTypeTag{ .number = value } };
    }

    pub fn asBool(self: Value) bool {
        return @as(bool, self.data.bool);
    }

    pub fn asNumber(self: Value) f64 {
        return @as(f64, self.data.number);
    }

    pub fn isBool(self: Value) bool {
        return self.type == .bool;
    }
};

pub const ValueTypeTag = packed union { bool: bool, nil: void, number: f64 };

test "Tagged unions have correct size (18.1)" {
    var v = ValueTypeTag{ .bool = true };
    try std.testing.expectEqual(8, @sizeOf(@TypeOf(v)));

    v = ValueTypeTag{ .number = 1.0 };
    try std.testing.expectEqual(8, @sizeOf(@TypeOf(v)));

    v = ValueTypeTag{ .nil = {} };
    try std.testing.expectEqual(8, @sizeOf(@TypeOf(v)));
}

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
                    return err;
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

        var value = Value.newNumber(4.2);
        try values.write(value);

        try std.testing.expect(values.values.ptr[0].data.number == 4.20);
        try std.testing.expect(values.capacity == 8);
        try std.testing.expect(values.count == 1);
    }
}
