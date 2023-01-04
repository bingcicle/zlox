const Parser = @This();

const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig").Chunk;

current: ?Token,
previous: ?Token,
hadError: bool,
panicMode: bool,
compilingChunk: Chunk,

pub fn makeConstant(self: *Parser, value: Value) !u8 {
    var constant = self.compilingChunk.addConstant(value);
    if (constant > 255) {
        return error.TooManyConstants;
    }

    return constant;
}

pub fn errorAtCurrent(self: *Parser, msg: []const u8) void {
    if (self.panicMode) return;
    self.panicMode = true;
    errorAt(self.current.?, msg);
}

pub fn number(self: *Parser) void {
    var value: f64 = std.fmt.parseFloat(self.previous.start);
    emitConstant(value);
}

pub fn consume(self: *Parser, scanner: anytype, token_type: TokenType, msg: []const u8) void {
    if (self.current.?.type == token_type) {
        advance(self, scanner);
        return;
    }

    errorAtCurrent(self, msg);
}

pub fn emitReturn(self: *Parser) void {
    emitByte(@enumToInt(Opcode.op_return), self.?);
}

pub fn emitByte(byte: u8, self: ?*Parser) void {
    if (self) |safe_parser| {
        try safe_parser.compilingChunk.writeChunk(byte, safe_parser.previous.line);
    }
}

pub fn emitBytes(
    chunk: anytype,
    byte1: u8,
    byte2: u8,
    self: *Parser,
) void {
    emitByte(chunk, byte1, self);
    emitByte(chunk, byte2, self);
}

pub fn emitConstant(self: *Parser, value: Value) void {
    emitBytes(Opcode.op_constant, self.makeConstant(self.compilingChunk, value));
}

pub fn advance(self: *Parser, scanner: anytype) void {
    self.previous = self.current;

    while (true) {
        self.current = scanner.scanToken();

        if (self.current.?.type != TokenType.err) {
            break;
        }

        errorAtCurrent(self, "");
        self.hadError = true;
    }
}

pub fn errorAt(token: Token, msg: []const u8) void {
    std.debug.print("[line {d}] Error", .{token.line});

    switch (token.type) {
        TokenType.eof => std.debug.print(" at end", .{}),
        TokenType.err => {},
        else => std.debug.print(" at {d} {d}", .{ token.length, token.start }),
    }

    std.debug.print(": {s}\n", .{msg});
}

test {
    std.testing.refAllDecls(@This());
}
