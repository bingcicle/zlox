const Parser = @This();

const debug = @import("debug.zig");
const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const Opcode = @import("opcode").Opcode;
const Value = @import("value.zig").Value;
const Chunk = @import("chunk.zig");
const Precedence = @import("Compiler.zig").Precedence;
const Scanner = @import("Scanner.zig");

current: ?Token,
previous: ?Token,
had_error: bool,
panic_mode: bool,
scanner: *Scanner,

pub fn errorAtCurrent(self: *Parser, msg: []const u8) void {
    if (self.panic_mode) return;
    self.panic_mode = true;

    if (self.current) |safe_current| {
        self.errorAt(safe_current, msg);
    }
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
