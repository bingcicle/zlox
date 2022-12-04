const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;
const Chunk = @import("main.zig").Chunk;
const WriteError = std.os.WriteError;

pub fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

pub fn constantInstruction(name: []const u8, chunk: anytype, offset: usize) usize {
    var constant = chunk.code.ptr[offset + 1];
    std.debug.print("{s} {d} ", .{ name, constant });

    std.debug.print("{}\n", .{chunk.constants.values.ptr[constant]});
    return offset + 2;
}

pub fn disassembleInstruction(chunk: anytype, offset: usize) usize {
    std.debug.print("{d} ", .{offset});

    if (offset > 0 and chunk.lines.ptr[offset] == chunk.lines.ptr[offset - 1]) {
        std.debug.print("  | ", .{});
    } else {
        std.debug.print("{d} ", .{chunk.lines.ptr[offset]});
    }
    var instruction = chunk.code.ptr[offset];
    switch (@intToEnum(Opcode, instruction)) {
        Opcode.op_return => {
            return simpleInstruction("OP_RETURN", offset);
        },
        Opcode.op_constant => {
            return constantInstruction("OP_CONSTANT", chunk, offset);
        },
    }
}

pub fn disassembleChunk(chunk: anytype, name: []const u8, writer: anytype) WriteError!void {
    _ = try writer.print("\n== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count) {
        offset = disassembleInstruction(chunk, offset);
    }
}
