const Parser = @This();

const debug = @import("debug.zig");
const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const Precedence = @import("Compiler.zig").Precedence;
const Scanner = @import("Scanner.zig");

current: ?Token,
previous: ?Token,
had_error: bool,
panic_mode: bool,
compiling_chunk: *Chunk,
scanner: *Scanner,

const ParseRule = struct {
    prefix: ?*const fn (*Parser) anyerror!void,
    infix: ?*const fn (*Parser) anyerror!void,
    precedence: Precedence,
};

fn getRule(token_type: TokenType) ParseRule {
    return switch (token_type) {
        TokenType.left_paren => ParseRule{
            .prefix = grouping,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.minus => ParseRule{
            .prefix = unary,
            .infix = binary,
            .precedence = Precedence.term,
        },
        TokenType.plus => ParseRule{
            .prefix = null,
            .infix = binary,
            .precedence = Precedence.term,
        },
        TokenType.slash,
        TokenType.star,
        => ParseRule{
            .prefix = null,
            .infix = binary,
            .precedence = Precedence.factor,
        },
        TokenType.number => ParseRule{
            .prefix = number,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.false => ParseRule{
            .prefix = literal,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.true => ParseRule{
            .prefix = literal,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.nil => ParseRule{
            .prefix = literal,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.bang => ParseRule{
            .prefix = unary,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.equal_equal => ParseRule{
            .prefix = null,
            .infix = binary,
            .precedence = Precedence.equality,
        },
        TokenType.greater,
        TokenType.greater_equal,
        TokenType.less,
        TokenType.less_equal,
        => ParseRule{
            .prefix = null,
            .infix = binary,
            .precedence = Precedence.comparison,
        },
        else => ParseRule{
            .prefix = null,
            .infix = null,
            .precedence = Precedence.none,
        },
    };
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
        self.errorAt(safe_current, msg);
    }
}

pub fn number(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        var string = self.scanner.source[safe_previous.start..(safe_previous.start + safe_previous.length)];
        try self.emitConstant(Value.newNumber(try std.fmt.parseFloat(f64, string)));
    }
}

pub fn literal(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        switch (safe_previous.type) {
            TokenType.false => try self.emitByte(@enumToInt(Opcode.op_false)),
            TokenType.nil => try self.emitByte(@enumToInt(Opcode.op_nil)),
            TokenType.true => try self.emitByte(@enumToInt(Opcode.op_true)),
            else => unreachable,
        }
    }
}

pub fn expression(self: *Parser) !void {
    try self.parsePrecedence(Precedence.assignment);
}

pub fn parsePrecedence(self: *Parser, precedence: Precedence) !void {
    self.advance();

    if (self.previous) |safe_previous| {
        var prefixRule = getRule(safe_previous.type).prefix;

        if (prefixRule) |safeRule| {
            try @call(.auto, safeRule, .{self});
        } else {
            self.parserError("Expect expression.");
            return;
        }

        while (@enumToInt(precedence) <= @enumToInt(getRule(self.current.?.type).precedence)) {
            self.advance();
            if (self.previous) |inner_safe_previous| {
                var infixRule = getRule(inner_safe_previous.type).infix;
                if (infixRule) |safeInfix| {
                    try @call(.auto, safeInfix, .{self});
                } else {
                    break;
                }
            }
        }
    }
}

pub fn grouping(self: *Parser) !void {
    try self.expression();
    self.consume(TokenType.right_paren, "Expect ')' after expression.");
}

pub fn binary(self: *Parser) !void {
    if (self.previous) |safe_previous| {
        var operator_type: TokenType = safe_previous.type;
        var rule = getRule(operator_type);
        try self.parsePrecedence(@intToEnum(Precedence, (@enumToInt(rule.precedence) + 1)));

        return switch (operator_type) {
            TokenType.bang_equal => self.emitBytes(
                @enumToInt(Opcode.op_equal),
                @enumToInt(Opcode.op_not),
            ),
            TokenType.equal_equal => self.emitByte(@enumToInt(Opcode.op_equal)),
            TokenType.greater => self.emitByte(@enumToInt(Opcode.op_greater)),
            TokenType.greater_equal => self.emitBytes(
                @enumToInt(Opcode.op_less),
                @enumToInt(Opcode.op_not),
            ),
            TokenType.less => self.emitByte(@enumToInt(Opcode.op_less)),
            TokenType.less_equal => self.emitBytes(
                @enumToInt(Opcode.op_greater),
                @enumToInt(Opcode.op_not),
            ),
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

        // Compile the operand.
        try self.parsePrecedence(Precedence.unary);

        return switch (operator_type) {
            TokenType.bang => self.emitByte(@enumToInt(Opcode.op_not)),
            TokenType.minus => self.emitByte(@enumToInt(Opcode.op_negate)),
            else => unreachable,
        };
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
        .scanner = &scanner,
    };

    try parser.unary();
    defer chunk.deinit();

    const writer = std.io.getStdOut().writer();
    try debug.disassembleChunk(parser.compiling_chunk, "test chunk", writer);
}

pub fn consume(self: *Parser, token_type: TokenType, msg: []const u8) void {
    if (self.current) |safe_current| {
        if (std.meta.eql(safe_current.type, token_type)) {
            self.advance();
            return;
        }

        self.errorAtCurrent(msg);
    }
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

pub fn advance(self: *Parser) void {
    self.previous = self.current;

    while (true) {
        self.current = self.scanner.scanToken();

        if (self.current) |safe_current| {
            if (safe_current.type != TokenType.err) {
                break;
            }
        }

        self.errorAtCurrent("ok");
    }
}

pub fn parserError(self: *Parser, msg: []const u8) void {
    if (self.previous) |safe_previous| {
        self.errorAt(safe_previous, msg);
    }
}

pub fn errorAt(self: *Parser, token: Token, msg: []const u8) void {
    if (self.panic_mode) return;
    self.panic_mode = true;
    std.debug.print("[line {d}] Error", .{token.line});

    switch (token.type) {
        TokenType.eof => std.debug.print(" at end", .{}),
        TokenType.err => {},
        else => std.debug.print(" at {d} {d}", .{ token.start, token.start + token.length }),
    }

    std.debug.print(": {s}\n", .{msg});
    self.had_error = true;
}
