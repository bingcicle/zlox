const std = @import("std");

const Scanner = @import("Scanner.zig");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode.zig").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const debug = @import("debug.zig");

const Parser = @import("Parser.zig");
const ChunkType = Chunk();

pub fn endCompiler(parser: *Parser) !void {
    try parser.emitReturn();
}

pub fn compile(source: []const u8, chunk: *Chunk) !bool {
    var scanner = Scanner.init(source);

    var parser = Parser{
        .current = null,
        .previous = null,
        .had_error = false,
        .panic_mode = false,
        .compiling_chunk = chunk,
        .scanner = scanner,
    };

    parser.advance();
    parser.expression();
    parser.consume(TokenType.eof, "Expect end of expression");

    try endCompiler(&parser);
    return !parser.had_error;
}

pub const Precedence = enum(u16) {
    None = 0x0,
    Assignment = 0x1, // =
    Or = 0x2, // or
    And = 0x3, // and
    Equality = 0x4, // == !=
    Comparison = 0x5, // < > <= >=
    Term = 0x6, // + =
    Factor = 0x7, // * /
    Unary = 0x8, // ! -
    Call = 0x9, // . ()
    Primary = 0x10,
};

test "compile" {
    var source = "var a = \"a\"";
    var chunk = Chunk.init(std.testing.allocator);
    var had_error = try compile(source, &chunk);
    defer chunk.deinit();

    try std.testing.expect(had_error);

    const writer = std.io.getStdOut().writer();
    try debug.disassembleChunk(&chunk, "test compile", writer);
}
