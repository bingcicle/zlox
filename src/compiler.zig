const std = @import("std");
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

pub fn compile(source: []const u8) void {
    var scanner = Scanner().init(source);

    compileLoop: while (true) {
        var token: Token = scanner.scanToken();

        std.debug.print("scanned: {any}\n", .{token});

        if (std.meta.eql(token.type, TokenType.eof)) {
            break :compileLoop;
        }
    }

    std.debug.print("\ncompiled.\n", .{});

    return;
}
