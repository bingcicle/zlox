const Parser = @This();

const debug = @import("debug.zig");
const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const Precedence = @import("compiler.zig").Precedence;
const Scanner = @import("Scanner.zig");

current: ?Token,
previous: ?Token,
had_error: bool,
panic_mode: bool,
compiling_chunk: *Chunk,
scanner: Scanner,

const TokenToParseRule = struct { TokenType, ParseRule };

const Fn = union {
    grouping: ?*const fn (*Parser) anyerror!void,
    number: ?*const fn (*Parser) anyerror!void,
    unary: ?*const fn (*Parser) anyerror!void,
    binary: ?*const fn (*Parser) anyerror!void,
};

const ParseRule = struct {
    prefix: ?Fn,
    infix: ?Fn,
    precedence: Precedence,
};

fn getRule(token_type: TokenType) ParseRule {
    return switch (token_type) {
        TokenType.left_paren => ParseRule{
            .prefix = Fn{ .grouping = grouping },
            .infix = null,
            .precedence = Precedence.none,
        },

        TokenType.minus => ParseRule{
            .prefix = Fn{ .unary = unary },
            .infix = Fn{ .binary = binary },
            .precedence = Precedence.none,
        },
        TokenType.plus,
        TokenType.slash,
        TokenType.star,
        => ParseRule{
            .prefix = null,
            .infix = Fn{ .binary = binary },
            .precedence = Precedence.none,
        },
        TokenType.number => ParseRule{
            .prefix = Fn{ .number = number },
            .infix = null,
            .precedence = Precedence.none,
        },
        else => ParseRule{
            .prefix = null,
            .infix = null,
            .precedence = Precedence.none,
        },
    };
}

test "parse precedence expects prefix parser" {
    {
        const prefix = getRule(TokenType.left_paren).prefix;
        if (prefix) |safe_prefix| {
            try std.testing.expectEqual(@TypeOf(safe_prefix), Parser.Fn);
        }
    }
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
    self.parsePrecedence(Precedence.assignment);
}

pub fn parsePrecedence(self: *Parser, precedence: Precedence) void {
    self.advance();

    if (self.previous) |safe_previous| {
        var prefixRule = getRule(safe_previous.type).prefix;
        if (prefixRule) |safeRule| {
            _ = safeRule;
        }

        if (self.current) |safe_current| {
            while (@enumToInt(precedence) <= @enumToInt(getRule(safe_current.type).precedence)) {
                self.advance();
                var infixRule = getRule(safe_previous.type).infix;
                _ = infixRule;
            }
        }
    } else {
        self.parserError("Expect expression.");
        return;
    }
}

pub fn grouping(self: *Parser) !void {
    self.expression();
    self.consume(TokenType.right_paren, "Expect ')' after expression.");
}

pub fn binary(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        var operator_type: TokenType = safe_previous.type;

        var rule = getRule(operator_type);
        self.parsePrecedence(rule.precedence);

        return switch (operator_type) {
            TokenType.plus => self.emitByte(@enumToInt(Opcode.op_add)),
            TokenType.minus => self.emitByte(@enumToInt(Opcode.op_subtract)),
            TokenType.star => self.emitByte(@enumToInt(Opcode.op_multiply)),
            TokenType.slash => self.emitByte(@enumToInt(Opcode.op_divide)),
            else => unreachable,
        };
    }
}

pub fn unary(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        var operator_type: TokenType = safe_previous.type;
        std.debug.print("\n-- OK --\n {any}\n", .{self.previous});

        // Compile the operand.
        self.parsePrecedence(Precedence.unary);

        switch (operator_type) {
            TokenType.minus => {
                return try self.emitByte(@enumToInt(Opcode.op_negate));
            },
            else => unreachable,
        }
    }
}

test "unary" {
    var scanner = Scanner.init("");
    var chunk = Chunk.init(std.testing.allocator);

    var previous = Token{
        .type = TokenType.minus,
        .start = 0,
        .length = 1,
        .line = 1,
    };

    var current = Token{
        .type = TokenType.identifier,
        .start = 2,
        .length = 1,
        .line = 1,
    };
    var parser = Parser{
        .current = current,
        .previous = previous,
        .had_error = false,
        .panic_mode = false,
        .compiling_chunk = &chunk,
        .scanner = scanner,
    };

    try parser.unary();
    defer chunk.deinit();

    const writer = std.io.getStdOut().writer();
    try debug.disassembleChunk(parser.compiling_chunk, "test chunk", writer);
}

pub fn consume(self: *Parser, token_type: TokenType, msg: []const u8) void {
    if (self.current) |safe_current| {
        if (safe_current.type == token_type) {
            self.advance();
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
        _ = try self.compiling_chunk.writeChunk(byte, safe_previous.line);
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

pub fn advance(self: *Parser) void {
    self.previous = self.current;

    advanceLoop: while (true) {
        self.current = self.scanner.scanToken();

        if (self.current) |safe_current| {
            if (safe_current.type != TokenType.err) {
                break :advanceLoop;
            }
        }

        self.errorAtCurrent("error");
    }
}

pub fn parserError(self: *Parser, msg: []const u8) void {
    if (self.previous) |safe_previous| {
        errorAt(safe_previous, msg);
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
