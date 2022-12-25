const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

const print = std.debug.print;

pub fn Scanner() type {
    return struct {
        const Self = @This();

        source: []const u8,
        start: usize,
        current: usize,
        line: usize,

        pub fn init(source: []const u8) Self {
            return Self{
                .source = source,
                .start = 0,
                .current = 0,
                .line = 1,
            };
        }

        pub fn scanToken(self: *Self) Token {
            self.skipWhitespace();

            self.start = self.current;

            if (self.isAtEnd()) {
                return Token{
                    .type = TokenType.eof,
                    .start = 0,
                    .length = 0,
                    .line = 0,
                };
            }

            var c = self.advance();

            if (self.isAlpha(c)) return self.parseIdentifier();
            if (self.isDigit(c)) return self.parseNumber();

            var token = switch (c) {
                '(' => self.createToken(TokenType.left_paren),
                ')' => self.createToken(TokenType.right_paren),
                '{' => self.createToken(TokenType.left_brace),
                '}' => self.createToken(TokenType.right_brace),
                ';' => self.createToken(TokenType.semicolon),
                ',' => self.createToken(TokenType.comma),
                '.' => self.createToken(TokenType.dot),
                '-' => self.createToken(TokenType.minus),
                '+' => self.createToken(TokenType.plus),
                '/' => self.createToken(TokenType.slash),
                '*' => self.createToken(TokenType.star),
                '!' => switch (self.match('=')) {
                    true => self.createToken(TokenType.bang_equal),
                    false => self.createToken(TokenType.bang),
                },
                '=' => switch (self.match('=')) {
                    true => self.createToken(TokenType.equal_equal),
                    false => self.createToken(TokenType.equal),
                },
                '<' => switch (self.match('=')) {
                    true => self.createToken(TokenType.less_equal),
                    false => self.createToken(TokenType.less),
                },
                '>' => switch (self.match('=')) {
                    true => self.createToken(TokenType.greater_equal),
                    false => self.createToken(TokenType.greater),
                },
                '"' => self.parseString(),
                else => self.createToken(TokenType.err),
            };

            return token;
        }

        fn parseString(self: *Self) Token {
            while (true) {
                var peeked: ?u8 = self.peek();

                if (peeked) |safe_peeked| {
                    if (safe_peeked == '"' or self.isAtEnd()) {
                        _ = self.advance();
                        return self.createToken(TokenType.string);
                    }

                    var next_peeked: ?u8 = self.peek();

                    if (next_peeked) |next_peeked_safe| {
                        if (next_peeked_safe == '\n') {
                            self.line += 1;
                        }

                        _ = self.advance();
                    }
                } else {
                    return self.createToken(TokenType.err);
                }
            }

            if (self.isAtEnd()) {
                return self.createToken(TokenType.err);
            }
        }

        fn parseNumber(self: *Self) Token {
            while (true) {
                var peeked: ?u8 = self.peek();

                if (peeked) |safe_peeked| {
                    var peeked_next: ?u8 = self.peekNext();
                    if (peeked_next) |safe_peeked_next| {
                        if (safe_peeked == '.' and self.isDigit(safe_peeked_next)) {
                            // consume .
                            _ = self.advance();

                            parseFracWhile: while (true) {
                                var fractional_peeked: ?u8 = self.peek();

                                if (fractional_peeked) |safe_fractional_peeked| {
                                    if (!self.isDigit(safe_fractional_peeked)) {
                                        return self.createToken(TokenType.number);
                                    }
                                } else {
                                    break :parseFracWhile;
                                }

                                _ = self.advance();
                            }
                        }
                    }

                    if (!self.isDigit(safe_peeked)) {
                        return self.createToken(TokenType.number);
                    } else {
                        _ = self.advance();
                    }
                } else {
                    return self.createToken(TokenType.err);
                }
            }
        }

        fn parseIdentifier(self: *Self) Token {
            parseIdentLoop: while (true) {
                var peeked: ?u8 = self.peek();

                if (peeked) |safe_peeked| {
                    if (!self.isAlpha(safe_peeked) and !self.isDigit(safe_peeked)) {
                        break :parseIdentLoop;
                    }

                    _ = self.advance();
                } else {
                    break :parseIdentLoop;
                }
            }
            return self.createToken(TokenType.identifierType(self));
        }

        fn match(self: *Self, expected: u8) bool {
            if (self.isAtEnd()) return false;
            if (self.source[self.current] != expected) return false;

            self.current += 1;
            return true;
        }

        fn advance(self: *Self) u8 {
            var current = self.source[self.current];
            self.current += 1;
            return current;
        }

        fn createToken(self: *Self, token_type: TokenType) Token {
            return Token{
                .type = token_type,
                .start = self.start,
                .length = self.current - self.start,
                .line = self.line,
            };
        }

        pub fn peek(self: Self) ?u8 {
            if (self.isAtEnd()) {
                return null;
            } else {
                return self.source[self.current];
            }
        }

        fn peekNext(self: Self) ?u8 {
            if (self.isAtEnd() or self.current + 1 >= self.source.len) {
                return null;
            } else {
                return self.source[self.current + 1];
            }
        }

        fn skipWhitespace(self: *Self) void {
            skip: while (true) {
                var c: ?u8 = self.peek();
                if (c) |safe_c| {
                    switch (safe_c) {
                        ' ', '\r', '\t' => {
                            _ = self.advance();
                            break :skip;
                        },
                        '/' => {
                            var next: ?u8 = self.peekNext();
                            if (next) |safe_next| {
                                if (safe_next == '/') {
                                    var peeked: ?u8 = self.peek();
                                    if (peeked) |safe_peeked| {
                                        while (safe_peeked != '\n' and !self.isAtEnd()) {
                                            _ = self.advance();
                                        }
                                    } else {
                                        return;
                                    }
                                }
                            }
                            break :skip;
                        },
                        '\n' => {
                            self.line += 1;
                            _ = self.advance();
                            break :skip;
                        },
                        else => return,
                    }
                } else {
                    return;
                }
            }
        }

        fn isDigit(self: Self, c: u8) bool {
            _ = self;
            return c >= '0' and c <= '9';
        }

        fn isAlpha(self: Self, c: u8) bool {
            _ = self;
            return (c >= 'a' and c <= 'z') or
                (c >= 'A' and c <= 'Z') or c == '_';
        }

        fn isAtEnd(self: Self) bool {
            return self.current >= self.source.len;
        }
    };
}
