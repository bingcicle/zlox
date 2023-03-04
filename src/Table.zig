const std = @import("std");
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;
const VM = @import("vm").VirtualMachine;
const ArrayList = std.ArrayList;
const Obj = @import("Object.zig");

const Table = @This();

const TABLE_MAX_LOAD: f16 = 0.75;

count: usize,
capacity: usize,
entries: []Entry,
allocator: std.mem.Allocator,

pub const Entry = struct {
    key: ?*Obj.ObjString,
    value: Value,
};

pub fn init(allocator: std.mem.Allocator) !Table {
    return Table{
        .count = 0,
        .capacity = 0,
        .entries = &[_]Entry{},
        .allocator = allocator,
    };
}

pub fn free(self: *Table) void {
    self.allocator.free(self.entries);
    self.entries = ArrayList(Entry).init();
}

pub fn set(self: *Table, key: *Obj.ObjString, value: Value) !bool {
    if (@intToFloat(f16, self.count + 1) > @intToFloat(f16, self.capacity) * TABLE_MAX_LOAD) {
        try self.adjustCapacity();
    }

    var entry = self.findEntry(key);

    var is_new_key = entry.key == null;

    if (is_new_key and Value.isNil(entry.value)) {
        self.count += 1;
    }

    entry.key = key;
    entry.value = value;

    return is_new_key;
}

pub fn get(self: *Table, key: *Obj.ObjString, value: *Value) bool {
    if (self.count == 0) return false;

    var entry = self.findEntry(key);
    if (entry.key != null) {
        value.* = entry.value;

        return true;
    }

    return false;
}

pub fn delete(self: *Table, key: *Obj.ObjString) bool {
    if (self.count == 0) return false;

    var entry: *Entry = self.findEntry(key);
    if (entry.key == null) {
        return false;
    }

    entry.key = null;
    entry.value = Value.newBool(true);
    return true;
}

fn adjustCapacity(self: *Table) !void {
    const new_capacity = if (self.capacity < 8) 8 else self.capacity * 2;
    var entries = try self.allocator.alloc(Entry, new_capacity);

    var i: usize = 0;
    while (i < new_capacity) : (i += 1) {
        entries[i].key = null;
        entries[i].value = Value.newNil();
    }

    i = 0;
    self.count = 0;
    while (i < self.capacity) : (i += 1) {
        var entry = self.entries[i];
        if (entry.key) |safe_key| {
            var dest = self.findEntry(safe_key);
            dest.key = entry.key;
            dest.value = entry.value;
            self.count += 1;
        } else {
            continue;
        }
    }

    self.allocator.free(self.entries);
    self.entries = entries;
    self.capacity = new_capacity;
}

pub fn findEntry(self: *Table, key: *Obj.ObjString) *Entry {
    // var index = if (self.capacity > 0) key.hash % self.capacity else 0;
    var index = key.hash % self.capacity;

    var tombstone: ?*Entry = null;
    while (true) {
        var entry = &self.entries[index];

        if (entry.key) |safe_key| {
            if (safe_key == key) return entry;
        } else {
            if (Value.isNil(entry.value)) {
                if (tombstone) |safe_tombstone| {
                    return safe_tombstone;
                }
                return entry;
            } else {
                if (tombstone == null) {
                    tombstone = entry;
                }
            }
        }
        index = (index + 1) % self.capacity;
    }
}

pub fn findString(self: *Table, chars: []const u8, hash: usize) ?*Obj.ObjString {
    if (self.count == 0) return null;

    var index = @mod(hash, self.capacity);

    while (true) {
        var entry = self.entries[index];

        if (entry.key) |safe_key| {
            if (safe_key.chars.len == chars.len and
                safe_key.hash == hash)
            {
                return safe_key;
            }
        } else {
            if (Value.isNil(entry.value)) return null;
        }

        index = @mod((index + 1), self.capacity);
    }
}

pub fn deinit(self: *Table) void {
    self.allocator.free(self.entries);
}

test "simple table" {
    var allocator = std.testing.allocator;
    var table = try Table.init();

    var vm = VM.init(allocator, false);
    defer vm.deinit();
    var my_string = "test";
    var hash = Obj.ObjString.hash(my_string);
    var str = try Obj.ObjString.create(&vm, allocator, my_string, hash);

    var obj = vm.objects;
    _ = obj;
    var value = Value.newObj(&str.obj);
    _ = table.set(str, value);
}
