const std = @import("std");
const Scanner = @import("scanner.zig");

pub const TokenType = enum {
    const Self = @This();
    // Single-character tokens.
    left_paren,
    right_paren,

    left_brace,
    right_brace,

    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,

    // One or two character tokens
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,

    // Literals
    identifier,
    string,
    number,

    // Keywords
    _and,
    class,
    _else,
    false,
    _for,
    fun,
    _if,
    nil,
    _or,
    print,
    _return,
    super,
    this,
    true,
    variable,
    _while,
    err,
    eof,

    fn checkKeyword(
        scanner: *Scanner,
        start: usize,
        length: usize,
        rest: []const u8,
        keyword: Self,
    ) Self {
        if ((scanner.current - scanner.start) == (start + length) and std.mem.eql(
            u8,
            scanner.source[(scanner.start + start)..(scanner.start + start + length)],
            rest,
        )) {
            return keyword;
        }

        return Self.identifier;
    }

    pub fn identifierType(scanner: *Scanner) Self {
        return switch (scanner.source[scanner.start]) {
            'a' => checkKeyword(scanner, 1, 2, &"nd".*, Self._and),
            'c' => checkKeyword(scanner, 1, 4, &"lass".*, Self.class),
            'e' => checkKeyword(scanner, 1, 3, &"lse".*, Self._else),
            'f' => {
                var f_token: TokenType = undefined;
                if (scanner.current - scanner.start > 1) {
                    f_token = switch (scanner.source[scanner.start + 1]) {
                        'a' => checkKeyword(scanner, 2, 3, "lse", TokenType.false),
                        'o' => checkKeyword(scanner, 2, 1, "r", TokenType._or),
                        'u' => checkKeyword(scanner, 2, 1, "n", TokenType.fun),
                        else => Self.identifier,
                    };
                    return f_token;
                } else {
                    return Self.identifier;
                }

                return f_token;
            },
            'i' => checkKeyword(scanner, 1, 1, &"f".*, Self._if),
            'n' => checkKeyword(scanner, 1, 2, &"il".*, Self.nil),
            'o' => checkKeyword(scanner, 1, 1, &"r".*, Self._or),
            'p' => checkKeyword(scanner, 1, 4, &"rint".*, Self.print),
            'r' => checkKeyword(scanner, 1, 5, &"eturn".*, Self._return),
            's' => checkKeyword(scanner, 1, 4, &"uper".*, Self.super),
            't' => {
                var t_token: TokenType = undefined;
                if (scanner.current - scanner.start > 1) {
                    t_token = switch (scanner.source[scanner.start + 1]) {
                        'h' => checkKeyword(scanner, 2, 2, "is", TokenType.this),
                        'r' => checkKeyword(scanner, 2, 2, "ue", TokenType.true),
                        else => Self.identifier,
                    };

                    return t_token;
                } else {
                    return Self.identifier;
                }

                return t_token;
            },
            'v' => checkKeyword(scanner, 1, 2, &"ar".*, Self.variable),
            'w' => checkKeyword(scanner, 1, 4, &"hile".*, Self._while),
            else => Self.identifier,
        };
    }
};

pub const Token = struct {
    type: TokenType,
    start: usize,
    length: usize,
    line: u8,
};
