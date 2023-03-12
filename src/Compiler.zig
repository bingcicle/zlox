const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
locals: ArrayList(Local),
scope_depth: usize,

pub const Local = struct {
    name: Token,
    depth: isize,
};

const ParseRule = struct {
    prefix: ?*const fn (*Self, bool) anyerror!void,
    infix: ?*const fn (*Self, bool) anyerror!void,
    precedence: Precedence,
};

pub fn init(
    parser: *Parser,
    chunk: *Chunk,
    vm: *VM,
) Self {
    return Self{
        .parser = parser,
        .compiling_chunk = chunk,
        .allocator = vm.allocator,
        .vm = vm,
        .locals = ArrayList(Local).init(vm.allocator),
        .scope_depth = 0,
    };
}

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
        TokenType.identifier => ParseRule{
            .prefix = variable,
            .infix = null,
            .precedence = Precedence.none,
        },
        TokenType.string => ParseRule{
            .prefix = string,
            .infix = null,
            .precedence = Precedence.none,
        },

        TokenType._and => ParseRule{
            .prefix = null,
            .infix = and_,
            .precedence = Precedence._and,
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

        TokenType._or => ParseRule{
            .prefix = null,
            .infix = or_,
            .precedence = Precedence._or,
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

fn check(self: *Self, token_type: TokenType) bool {
    if (self.parser.current) |safe_current| {
        return safe_current.type == token_type;
    }

    return false;
}

pub fn match(self: *Self, token_type: TokenType) bool {
    if (!self.check(token_type)) {
        return false;
    }
    self.parser.advance();
    return true;
}

pub fn compile(self: *Self) !bool {
    std.debug.print("\n---------\n", .{});
    self.parser.advance();

    while (!self.match(TokenType.eof)) {
        try self.declaration();
    }

    try self.endCompiler();
    return !self.parser.had_error;
}

pub fn parsePrecedence(self: *Self, precedence: Precedence) !void {
    self.parser.advance();

    if (self.parser.previous) |safe_previous| {
        var prefixRule = getRule(safe_previous.type).prefix;
        var can_assign = @enumToInt(precedence) <= @enumToInt(Precedence.assignment);

        if (prefixRule) |safeRule| {
            try @call(.{}, safeRule, .{ self, can_assign });
        } else {
            self.parser.parserError("Expect expression.");
            return;
        }

        while (@enumToInt(precedence) <= @enumToInt(getRule(self.parser.current.?.type).precedence)) {
            self.parser.advance();
            if (self.parser.previous) |inner_safe_previous| {
                var infixRule = getRule(inner_safe_previous.type).infix;
                if (infixRule) |safeInfix| {
                    try @call(.{}, safeInfix, .{ self, can_assign });
                } else {
                    break;
                }

                if (can_assign and self.match(TokenType.equal)) {
                    return error.InvalidAssignment;
                }
            }
        }
    }
}

pub fn parseVariable(self: *Self, error_message: []const u8) !u8 {
    self.parser.consume(TokenType.identifier, error_message);

    try self.declareVariable();
    if (self.scope_depth > 0) return 0;

    return try self.identifierConstant(self.parser.previous.?);
}

pub fn markInitialized(self: *Self) void {
    if (self.scope_depth == 0) return;
    self.locals.items[self.locals.items.len - 1].depth = @intCast(isize, self.scope_depth);
}

pub fn defineVariable(self: *Self, global: u8) !void {
    if (self.scope_depth > 0) {
        self.markInitialized();
        return;
    }

    try self.emitBytes(@enumToInt(Opcode.op_define_global), global);
}

pub fn and_(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    var end_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump_if_false));

    try self.emitByte(@enumToInt(Opcode.op_pop));
    try self.parsePrecedence(Precedence._and);

    try self.patchJump(end_jump);
}

pub fn or_(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    var else_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump_if_false));
    var end_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump));

    try self.patchJump(else_jump);
    try self.emitByte(@enumToInt(Opcode.op_pop));

    try self.parsePrecedence(Precedence._or);
    try self.patchJump(end_jump);
}

pub fn identifierConstant(self: *Self, name: Token) !u8 {
    const obj_string = try Obj.ObjString.copy(
        self.vm,
        self.allocator,
        self.parser.scanner.source[(name.start)..(name.start + name.length)],
    );
    return try self.makeConstant(Value.newObj(&obj_string.obj));
}

pub fn declareVariable(self: *Self) !void {
    if (self.scope_depth == 0) return;

    var name = self.parser.previous.?;

    var i: usize = 0;
    while (i < self.locals.items.len) : (i += 1) {
        var local = self.locals.items[self.locals.items.len - 1 - i];
        if (local.depth != -1 and local.depth < self.scope_depth) {
            break;
        }

        if (std.mem.eql(
            u8,
            self.parser.scanner.source[name.start .. name.start + name.length],
            self.parser.scanner.source[local.name.start .. local.name.start + local.name.length],
        )) {
            return error.RedeclaredVariable;
        }
    }

    try self.addLocal(name);
}

pub fn addLocal(self: *Self, name: Token) !void {
    if (self.locals.items.len > std.math.maxInt(u8)) {
        return error.TooManyLocals;
    }
    var new_local = Local{
        .name = name,
        .depth = -1,
    };
    try self.locals.append(new_local);
}

pub fn expression(self: *Self) !void {
    try self.parsePrecedence(Precedence.assignment);
}

pub fn expressionStatement(self: *Self) !void {
    try self.expression();
    self.parser.consume(TokenType.semicolon, "Expect ';' after expression.");
    try self.emitByte(@enumToInt(Opcode.op_pop));
}

pub fn forStatement(self: *Self) !void {
    self.beginScope();
    self.parser.consume(TokenType.left_paren, "Expect '(' after 'for'.");
    if (self.match(TokenType.semicolon)) {
        // No initializer.
    } else if (self.match(TokenType.variable)) {
        try self.varDeclaration();
    } else {
        try self.expressionStatement();
    }

    var loop_start = self.compiling_chunk.count;
    var exit_jump: isize = -1;
    if (!self.match(TokenType.semicolon)) {
        try self.expression();
        self.parser.consume(TokenType.semicolon, "Expect ';'.");

        exit_jump = @intCast(isize, try self.emitJump(@enumToInt(Opcode.op_jump_if_false)));
        try self.emitByte(@enumToInt(Opcode.op_pop));
    }

    if (!self.match(TokenType.right_paren)) {
        var body_jump = try self.emitJump(@enumToInt(Opcode.op_jump));
        var increment_start = self.compiling_chunk.count;
        try self.expression();
        try self.emitByte(@enumToInt(Opcode.op_pop));
        self.parser.consume(TokenType.right_paren, "Expect ')' after for clauses.");

        try self.emitLoop(loop_start);
        loop_start = increment_start;
        try self.patchJump(body_jump);
    }

    try self.statement();
    try self.emitLoop(loop_start);

    if (exit_jump != -1) {
        try self.patchJump(@intCast(usize, exit_jump));
        try self.emitByte(@enumToInt(Opcode.op_pop));
    }

    try self.endScope();
}

fn ifStatement(self: *Self) !void {
    self.parser.consume(TokenType.left_paren, "Expect '(' after 'if'.");
    try self.expression();
    self.parser.consume(TokenType.right_paren, "Expect ')' after condition.");

    var then_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump_if_false));
    try self.emitByte(@enumToInt(Opcode.op_pop));
    try self.statement();

    var else_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump));

    try self.patchJump(then_jump);
    try self.emitByte(@enumToInt(Opcode.op_pop));

    if (self.match(TokenType._else)) try self.statement();
    try self.patchJump(else_jump);
}

fn emitJump(self: *Self, instruction: u8) !usize {
    try self.emitByte(instruction);
    try self.emitByte(0xff);
    try self.emitByte(0xff);
    return self.compiling_chunk.count - 2;
}

/// Goes back in the bytecode and replaces the operand at the given location
/// with the calculated jump offset.
fn patchJump(self: *Self, offset: usize) !void {
    var jump = self.compiling_chunk.count - offset - 2;

    if (jump > std.math.maxInt(u16)) {
        return error.InvalidJump;
    }

    self.compiling_chunk.code.ptr[offset] = @intCast(u8, jump >> 8) & 0xff;
    self.compiling_chunk.code.ptr[offset + 1] = @intCast(u8, jump) & 0xff;
}

pub fn declaration(self: *Self) !void {
    if (self.match(TokenType.variable)) {
        try self.varDeclaration();
    } else {
        try self.statement();
    }

    if (self.parser.panic_mode) {
        try self.synchronize();
    }
}

pub fn varDeclaration(self: *Self) !void {
    var global = try self.parseVariable("Expect variable name.");

    if (self.match(TokenType.equal)) {
        try self.expression();
    } else {
        try self.emitByte(@enumToInt(Opcode.op_nil));
    }

    self.parser.consume(TokenType.semicolon, "Expect ';' after variable declaration.");

    try self.defineVariable(global);
}

pub fn statement(self: *Self) !void {
    if (self.match(TokenType.print)) {
        try self.printStatement();
    } else if (self.match(TokenType._for)) {
        try self.forStatement();
    } else if (self.match(TokenType._if)) {
        try self.ifStatement();
    } else if (self.match(TokenType._while)) {
        try self.whileStatement();
    } else if (self.match(TokenType.left_brace)) {
        self.beginScope();
        try self.block();
        try self.endScope();
    } else {
        try self.expressionStatement();
    }
}

fn block(self: *Self) !void {
    while (!self.check(TokenType.right_brace) and !self.check(TokenType.eof)) {
        try self.declaration();
    }

    self.parser.consume(TokenType.right_brace, "Expect '}' after block.");
}

fn beginScope(self: *Self) void {
    self.scope_depth += 1;
}

fn endScope(self: *Self) !void {
    self.scope_depth -= 1;

    while (self.locals.items.len > 0 and
        self.locals.items[self.locals.items.len - 1].depth > self.scope_depth)
    {
        try self.emitByte(@enumToInt(Opcode.op_pop));
        _ = self.locals.pop();
    }
}

pub fn printStatement(self: *Self) !void {
    try self.expression();
    self.parser.consume(TokenType.semicolon, "Expect ';' after value.");
    try self.emitByte(@enumToInt(Opcode.op_print));
}

pub fn whileStatement(self: *Self) !void {
    var loop_start: usize = self.compiling_chunk.count;
    self.parser.consume(TokenType.left_paren, "Expect '(' after 'while'.");
    try self.expression();
    self.parser.consume(TokenType.right_paren, "Expect ')' after condition.");

    var exit_jump: usize = try self.emitJump(@enumToInt(Opcode.op_jump_if_false));
    try self.emitByte(@enumToInt(Opcode.op_pop));
    try self.statement();
    try self.emitLoop(loop_start);

    try self.patchJump(exit_jump);
    try self.emitByte(@enumToInt(Opcode.op_pop));
}

pub fn emitLoop(self: *Self, loop_start: usize) !void {
    try self.emitByte(@enumToInt(Opcode.op_loop));

    var offset: usize = self.compiling_chunk.count - loop_start + 2;
    if (offset > std.math.maxInt(u16)) return error.LoopBodyTooLarge;

    try self.emitByte((@intCast(u8, offset >> 8)) & 0xff);
    try self.emitByte(@intCast(u8, offset) & 0xff);
}

pub fn synchronize(self: *Self) !void {
    self.parser.panic_mode = false;

    while (self.parser.current.?.type != TokenType.eof) {
        if (self.parser.previous.?.type == TokenType.semicolon) return;

        switch (self.parser.current.?.type) {
            TokenType.class,
            TokenType.fun,
            TokenType.variable,
            TokenType._for,
            TokenType._if,
            TokenType._while,
            TokenType.print,
            TokenType._return,
            => return,
            else => {}, // do nothing
        }

        self.parser.advance();
    }
}

pub fn binary(self: *Self, can_assign: bool) !void {
    _ = can_assign;
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

pub fn string(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    if (self.parser.previous) |safe_token| {
        const obj_string = try Obj.ObjString.copy(
            self.vm,
            self.allocator,
            self.parser.scanner.source[(safe_token.start + 1)..(safe_token.start + safe_token.length - 1)],
        );
        try self.emitConstant(Value.newObj(&obj_string.obj));
    }
}

pub fn variable(self: *Self, can_assign: bool) !void {
    try self.namedVariable(self.parser.previous.?, can_assign);
}

pub fn namedVariable(self: *Self, name: Token, can_assign: bool) !void {
    var get_op: Opcode = undefined;
    var set_op: Opcode = undefined;
    var arg: u8 = undefined;
    var resolved_local = try self.resolveLocal(name);

    if (resolved_local != -1) {
        arg = @intCast(u8, resolved_local);
        get_op = Opcode.op_get_local;
        set_op = Opcode.op_set_local;
    } else {
        arg = try self.identifierConstant(name);
        get_op = Opcode.op_get_global;
        set_op = Opcode.op_set_global;
    }

    if (can_assign and self.match(TokenType.equal)) {
        try self.expression();
        try self.emitBytes(@enumToInt(set_op), arg);
    } else {
        try self.emitBytes(@enumToInt(get_op), arg);
    }
}

pub fn resolveLocal(self: *Self, name: Token) !isize {
    var i: usize = 0;
    while (i < self.locals.items.len) : (i += 1) {
        var local = self.locals.items[self.locals.items.len - 1 - i];

        if (std.mem.eql(
            u8,
            self.parser.scanner.source[name.start .. name.start + name.length],
            self.parser.scanner.source[local.name.start .. local.name.start + local.name.length],
        )) {
            if (local.depth == -1) {
                return error.ReadAndInitLocalVar;
            }
            return @intCast(isize, self.locals.items.len - 1 - i);
        }
    }

    return -1;
}

pub fn number(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    if (self.parser.previous) |safe_previous| {
        var string_ = self.parser.scanner.source[safe_previous.start..(safe_previous.start + safe_previous.length)];
        try self.emitConstant(Value.newNumber(try std.fmt.parseFloat(f64, string_)));
    }
}

pub fn literal(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    if (self.parser.previous) |safe_previous| {
        switch (safe_previous.type) {
            TokenType.false => try self.emitByte(@enumToInt(Opcode.op_false)),
            TokenType.nil => try self.emitByte(@enumToInt(Opcode.op_nil)),
            TokenType.true => try self.emitByte(@enumToInt(Opcode.op_true)),
            else => unreachable,
        }
    }
}

pub fn grouping(self: *Self, can_assign: bool) !void {
    _ = can_assign;
    try self.expression();
    self.parser.consume(TokenType.right_paren, "Expect ')' after expression.");
}

pub fn unary(self: *Self, can_assign: bool) !void {
    _ = can_assign;
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
    if (constant > std.math.maxInt(u8)) {
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

pub fn deinit(self: *Self) void {
    self.locals.deinit();
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
