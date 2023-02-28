const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const debug = @import("debug.zig");
const Parser = @import("Parser.zig");
const Obj = @import("Object.zig");
const VM = @import("vm.zig").VirtualMachine;

parser: *Parser,
compiling_chunk: *Chunk,
allocator: Allocator,
vm: *VM,

const ParseRule = struct {
    prefix: ?*const fn (*Self) anyerror!void,
    infix: ?*const fn (*Self) anyerror!void,
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
        TokenType.string => ParseRule{
            .prefix = string,
            .infix = null,
            .precedence = Precedence.none,
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

pub fn endCompiler(self: *Self) !void {
    try self.emitReturn();

    if (!self.parser.had_error) {
        const writer = std.io.getStdOut().writer();
        try debug.disassembleChunk(self.compiling_chunk, "code", writer);
    }

    return;
}

pub fn compile(self: *Self) !bool {
    self.parser.advance();
    try self.expression();
    self.parser.consume(TokenType.eof, "Expect end of expression");

    try self.endCompiler();
    return !self.parser.had_error;
}

pub fn parsePrecedence(self: *Self, precedence: Precedence) !void {
    self.parser.advance();

    if (self.parser.previous) |safe_previous| {
        var prefixRule = getRule(safe_previous.type).prefix;

        if (prefixRule) |safeRule| {
            try @call(.{}, safeRule, .{self});
        } else {
            self.parser.parserError("Expect expression.");
            return;
        }

        while (@enumToInt(precedence) <= @enumToInt(getRule(self.parser.current.?.type).precedence)) {
            self.parser.advance();
            if (self.parser.previous) |inner_safe_previous| {
                var infixRule = getRule(inner_safe_previous.type).infix;
                if (infixRule) |safeInfix| {
                    try @call(.{}, safeInfix, .{self});
                } else {
                    break;
                }
            }
        }
    }
}

pub fn expression(self: *Self) !void {
    try self.parsePrecedence(Precedence.assignment);
}

pub fn binary(self: *Self) !void {
    if (self.parser.previous) |safe_previous| {
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

pub fn string(self: *Self) !void {
    if (self.parser.previous) |safe_token| {
        const obj_string = try Obj.ObjString.copy(
            self.vm,
            self.allocator,
            self.parser.scanner.source[(safe_token.start + 1)..(safe_token.start + safe_token.length - 1)],
        );
        try self.emitConstant(Value.newObj(&obj_string.obj));
    }
}

pub fn number(self: *Self) !void {
    if (self.parser.previous) |safe_previous| {
        var string_ = self.parser.scanner.source[safe_previous.start..(safe_previous.start + safe_previous.length)];
        try self.emitConstant(Value.newNumber(try std.fmt.parseFloat(f64, string_)));
    }
}

pub fn literal(self: *Self) !void {
    if (self.parser.previous) |safe_previous| {
        switch (safe_previous.type) {
            TokenType.false => try self.emitByte(@enumToInt(Opcode.op_false)),
            TokenType.nil => try self.emitByte(@enumToInt(Opcode.op_nil)),
            TokenType.true => try self.emitByte(@enumToInt(Opcode.op_true)),
            else => unreachable,
        }
    }
}

pub fn grouping(self: *Self) !void {
    try self.expression();
    self.parser.consume(TokenType.right_paren, "Expect ')' after expression.");
}

pub fn unary(self: *Self) !void {
    if (self.parser.previous) |safe_previous| {
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

pub fn emitReturn(self: *Self) anyerror!void {
    try self.emitByte(@enumToInt(Opcode.op_return));
}

pub fn makeConstant(self: *Self, value: Value) !u8 {
    var constant = try self.compiling_chunk.addConstant(value);
    if (constant > 255) {
        return error.TooManyConstants;
    }

    return constant;
}
pub fn emitConstant(self: *Self, value: Value) !void {
    try self.emitBytes(@enumToInt(Opcode.op_constant), try self.makeConstant(value));
}

pub fn emitByte(self: *Self, byte: u8) anyerror!void {
    if (self.parser.previous) |safe_previous| {
        try self.compiling_chunk.writeChunk(byte, safe_previous.line);
    }
}

pub fn emitBytes(
    self: *Self,
    byte1: u8,
    byte2: u8,
) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

pub const Precedence = enum(u16) {
    none,
    assignment, // =
    _or, // or
    _and, // and
    equality, // == !=
    comparison, // < > <= >=
    term, // + =
    factor, // * /
    unary, // ! -
    call, // . ()
    primary,
};
