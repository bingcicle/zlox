const Parser = @This();

const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const Precedence = @import("compiler.zig").Precedence;

current: ?Token,
previous: ?Token,
had_error: bool,
panic_mode: bool,
compiling_chunk: Chunk,

const TokenToParseRule = struct { TokenType, ParseRule };

const Fn = union {
    number: ?*const fn (*Parser) @typeInfo(@typeInfo(@TypeOf(Parser.number)).Fn.return_type.?).ErrorUnion.error_set!void,
};

const ParseRule = struct {
    prefix: Fn,
    infix: ?*const fn () void,
    precedence: Precedence,
};

fn ParseFn(self: *Parser, scanner: anytype) void {
    _ = scanner;
    _ = self;
}

fn getRule(token_type: TokenType) !ParseRule {
    return switch (token_type) {
        TokenType.number => ParseRule{
            .prefix = Fn{ .number = number },
            .infix = null,
            .precedence = Precedence.None,
        },
        else => error.UnknownToken,
    };
}

test "ParseRuleMap" {
    _ = try getRule(TokenType.left_paren);
}

pub fn makeConstant(self: *Parser, value: Value) !u8 {
    var constant = try self.compiling_chunk.addConstant(value);
    if (constant > 255) {
        return error.TooManyConstants;
    }

    return constant;
}

pub fn errorAtCurrent(self: *Parser, msg: []const u8) void {
    if (self.panic_mode) return;
    self.panic_mode = true;

    if (self.current) |safe_current| {
        errorAt(safe_current, msg);
    }
}

pub fn number(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        var value: Value = Value{ .data = @intToFloat(f64, safe_previous.start) };

        try self.emitConstant(value);
    }
}

pub fn expression(self: *Parser) void {
    self.parsePrecedence(Precedence.Assignment);
}

pub fn parsePrecedence(self: *Parser, precedence: Precedence) void {
    _ = self;
    _ = precedence;
}

pub fn grouping(self: *Parser, scanner: anytype) !void {
    self.expression();
    self.consume(scanner, TokenType.right_paren, "Expect ')' after expression.");
}

pub fn binary(self: *Parser) void {
    var operator_type: TokenType = self.previous.type;

    // ParseRule* rule = getRule(operatorType);
    // parsePrecedence((Precedence)(rule->precedence + 1));

    switch (operator_type) {
        TokenType.plus => self.emitByte(Opcode.op_add),
        TokenType.minus => self.emitByte(Opcode.op_subtract),
        TokenType.star => self.emitByte(Opcode.op_multiply),
        TokenType.slash => self.emitByte(Opcode.op_divide),
        else => unreachable,
    }
}

pub fn unary(self: *Parser) void {
    var operator_type: TokenType = self.previous.type;

    // Compile the operand.
    self.parsePrecedence(Precedence.Unary);

    switch (operator_type) {
        TokenType.minus => {
            self.emitByte(Opcode.op_negate);
            return;
        },
        else => unreachable,
    }
}

pub fn consume(self: *Parser, scanner: anytype, token_type: TokenType, msg: []const u8) void {
    if (self.current) |safe_current| {
        if (safe_current.type == token_type) {
            self.advance(scanner);
            return;
        }
    }

    self.errorAtCurrent(msg);
}

pub fn emitReturn(self: *Parser) anyerror!void {
    try self.emitByte(@enumToInt(Opcode.op_return));
}

pub fn emitByte(self: *Parser, byte: u8) anyerror!void {
    if (self.previous) |safe_previous| {
        try self.compiling_chunk.writeChunk(byte, safe_previous.line);
    }
}

pub fn emitBytes(
    self: *Parser,
    byte1: u8,
    byte2: u8,
) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

pub fn emitConstant(self: *Parser, value: Value) !void {
    try self.emitBytes(@enumToInt(Opcode.op_constant), try self.makeConstant(value));
}

pub fn advance(self: *Parser, scanner: anytype) void {
    self.previous = self.current;

    while (true) {
        self.current = scanner.scanToken();

        if (self.current) |safe_current| {
            if (safe_current.type != TokenType.err) {
                break;
            }
        }

        self.errorAtCurrent("error");
        self.had_error = true;
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
