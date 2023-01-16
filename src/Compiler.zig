const std = @import("std");

const Compiler = @This();

const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const debug = @import("debug.zig");
const Parser = @import("Parser.zig");

pub fn endCompiler(parser: *Parser) !void {
    try parser.emitReturn();

    if (!parser.had_error) {
        const writer = std.io.getStdOut().writer();
        try debug.disassembleChunk(parser.compiling_chunk, "code", writer);
    }

    return;
}

pub fn compile(_: *Compiler, parser: *Parser) !bool {
    parser.advance();
    try parser.expression();
    parser.consume(TokenType.eof, "Expect end of expression");

    try endCompiler(parser);
    return !parser.had_error;
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
