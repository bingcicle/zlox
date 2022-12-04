const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;

pub fn growCapacity(capacity: usize) anyerror!usize {
    switch (capacity < 8) {
        true => return 8,
        false => return (capacity * 2),
    }
}

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}
