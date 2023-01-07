const std = @import("std");
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");

const Parser = @import("Parser.zig");
const ChunkType = Chunk();

pub fn endCompiler(parser: *Parser) !void {
    try parser.emitReturn();
}

pub fn compile(source: []const u8, chunk: Chunk) !bool {
    var scanner = Scanner().init(source);

    var parser = Parser{
        .current = null,
        .previous = null,
        .had_error = false,
        .panic_mode = false,
        .compiling_chunk = chunk,
    };

    parser.advance(&scanner);
    parser.expression();
    parser.consume(&scanner, TokenType.eof, "Expect end of expression");

    try endCompiler(&parser);
    return !parser.had_error;
}

pub const Precedence = enum {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + =
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};
