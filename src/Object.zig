const std = @import("std");
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;
const VM = @import("vm.zig").VirtualMachine;

const Obj = @This();

type: Type,
next: ?*Obj,

pub const Type = enum {
    String,
};

pub fn allocate(vm: *VM, allocator: Allocator, comptime T: type, obj_type: Type) !*Obj {
    const object = try allocator.create(T);
    object.obj = Obj{
        .type = obj_type,
        .next = vm.objects,
    };

    vm.objects = &object.obj;
    return &object.obj;
}

pub fn deinit(self: *Obj, allocator: Allocator) void {
    switch (self.type) {
        .String => self.asString().deinit(allocator),
    }
}

pub fn typeFromValue(value: Value) Type {
    return value.asObj().type;
}

pub fn print(value: Value) void {
    const as_obj = value.asObj();
    switch (as_obj.type) {
        .String => std.debug.print("{s}", .{as_obj.asString().chars}),
    }
}
pub const ObjString = struct {
    obj: Obj,
    chars: []const u8,

    pub fn copy(vm: *VM, allocator: Allocator, chars: []const u8) !*ObjString {
        const buffer = try allocator.alloc(u8, chars.len);

        std.mem.copy(u8, buffer, chars);
        const obj_str = try ObjString.create(vm, allocator, buffer);

        return obj_str;
    }

    pub fn create(vm: *VM, allocator: Allocator, chars: []const u8) !*ObjString {
        const obj_ptr = try Obj.allocate(vm, allocator, ObjString, .String);
        const obj_string = obj_ptr.asString();
        obj_string.* = ObjString{
            .obj = obj_ptr.*,
            .chars = chars,
        };
        return obj_string;
    }

    pub fn deinit(self: *ObjString, allocator: Allocator) void {
        allocator.free(self.chars);
        allocator.destroy(self);
    }
};

pub fn asString(self: *Obj) *ObjString {
    return @fieldParentPtr(ObjString, "obj", self);
}

test "basic strings test" {
    var allocator = std.testing.allocator;

    var chars = "hello world";
    var obj_string = try ObjString.copy(allocator, chars);
    try std.testing.expectEqualStrings(chars, obj_string.chars);
}
