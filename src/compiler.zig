const std = @import("std");
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig").Chunk;

const Parser = @import("Parser.zig");
const ChunkType = Chunk();

pub fn endCompiler(parser: *Parser) void {
    parser.emitReturn();
}

pub fn compile(source: []const u8, chunk: anytype) bool {
    var scanner = Scanner().init(source);

    var parser = Parser{
        .current = null,
        .previous = null,
        .hadError = false,
        .panicMode = false,
        .compilingChunk = chunk,
    };

    parser.advance(&scanner);
    //parser.expression();
    parser.consume(&scanner, TokenType.eof, "Expect end of expression");

    endCompiler(&parser);
    return !parser.hadError;
}
