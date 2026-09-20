## philosophy

### references

1. [Zigの禅](https://ziglang.org/documentation/master/#Zen)を完全継承する。
2. [Zigのスタイルガイド](https://ziglang.org/documentation/master/#Style-Guide)を踏襲するが、衝突する場合はこの文書を優先する。
3. Functional Core, Imperative Shell (FCIS)アーキテクチャを採択する。
4. その実践として[Impureim Sandwich](https://blog.ploeh.dk/2020/03/02/impureim-sandwich/)と[Sans I/O](https://sans-io.readthedocs.io/)に準拠する。

### complement 

FCISやImpureim Sandwichはしばしば[連続的なIOの組み合わせの複雑さを封じ込めるための木構造](https://blog.ploeh.dk/2017/07/24/combining-free-monads-in-haskell/)に発展する。\
これを回避しつつFCISを達成するために、次のことを認める:

- **『システムコールを発行しないステートフルな状態機械』はCore領域内において純粋である。**

「同じ一連の入力には同じ結果を返すこと」「カーネルに制御を渡さないこと」の二点を満たせば純粋とみなす。\
この機械はとても強力なので、クライスリ圏の力を借りずともCoreの純粋性を保つことができる([`Ref`](https://codeberg.org/ziglang/zig/src/tag/0.16.0/lib/std/http/HeadParser.zig))。

## naming conventions

- アンダースコアから始まるフィールド名は禁止 (e.g. `some_struct._somefield`) 
  - Zigにプライベートフィールドはない。ないものをあるように扱うのは避ける。
- `std.Io.Reader`/`std.Io.Writer`のパラメータ名は常に`source`/`sink`
  - `std.Io.File.Writer`等の具象Reader/Writerに`reader`/`writer`変数名を固定するため([`Ref`](https://youtu.be/f30PceqQWko?si=TMoQlhtOawuyw7gX&t=1154))。
 
## type and module imports 

- モジュールルートとライブラリルートはファイル開幕で参照拘束する
  ```zig
  const mylib = @import("mylib");
  const core = @import("core.zig");
  const builtin = @import("builtin");
  const std = @import("std");
  ```

- 名前空間をファイルトップレベルで参照拘束するのは禁止(完全修飾する)
  ```zig
  const time = std.time; // NG
  const path = std.fs.path; // NG 
  const controller = core.controller; // NG

  test {
      const testing = std.testing; // OK
  }
  ```

- 型はファイルトップレベルで参照拘束してよい
  ```zig
  const Io = std.Io;
  const Allocator = std.mem.Allocator;
  const Engine = @import("core/Engine.zig");
  const Client = mylib.socket.Client;
  ```

- 型の内部型は個別に拘束せずトップレベル型を経由して参照する
  ```zig
  pub fn save(sink: *Io.Writer, file: Io.File, stamp: Io.Timestamp) !void {...}
  ```

- ファイルスコープ定数と名前空間の拘束とを区別する
  ```zig
  const log = std.log.scoped(.engine); // OK
  const assert = std.debug.assert; // OK
  ```

## pass by value

- const参照渡し `fn func(arg: *const Struct)` を**基本的に避ける**
  - 読み取り専用: `fn func(arg: Struct)`、読み書き: `fn func(arg: *Struct)` を使う。
  - Zigは値渡しパラメータを自動でメモリ最適に最適化する。プログラマがサイズを計算して`*const`を指定する必要はない。
  - `*const Struct`は標準ライブラリに倣って構造体のアドレス同一性(`@fieldParentPtr`等)を要求する場合にのみ用いる。
  - C ABI境界では実際の呼び出し規約に従う。

## stack size 

- スタックサイズは64KBを想定して書く
  - 非同期基盤(io_uring等)やファイバー環境を考慮し、1MB/8MBの標準スタックを仮定しない。
  - 4KBを超えるローカル配列をスタックに置かない。
  - 再帰を避ける。末尾再帰指定子も現状は非LLVMバックエンドで動かないため避ける。

## memory principle

- 基礎: **Grouped Element Thinking** 
  - RAII的な都度の個別確保を避け、作業単位・データ集合ごとにまとめて確保する。
  - `ArenaAllocator` `FixedBufferAllocator` `ArrayList.initCapacity`
  
- 推奨: **Caller-Allocated Buffer** 
  - 可能な限り呼び出し元からバッファを受け取る。
    ```zig
    fn render(buffer: []f32) void
    ```
  
- 次善: **Caller-Passed Allocator** 
  - 動的確保が不可避かつ純粋性を必要としない場合は、引数で明示的に`Allocator`を受け取る。
    ```zig
    fn parse(arena: Allocator) !Ast
    ```

- 適宜: **長さがコンパイルタイム既知で小さい配列の値返し**
  - ZigのRVOにより 1→レジスタに乗る 2→呼び出し元スタックに直接書かれる(たくさんのメリットがある)。
    ```zig
    fn crcgen(object: Object) [16]u8 // 1. レジスタに乗る
    fn encode(data: Data) [64]u8     // 2. 呼び出し元スタックに書かれる
    ```

## error handling

- [エラーの分類](https://joeduffyblog.com/2016/02/07/the-error-model/#bugs-arent-recoverable-errors)を徹底する:
  1. **不変条件違反(バグ)**: プログラマのミス。`assert`で即座に落とす。
  2. **環境・システムエラー**: IO例外、OOM等。外部要因の失敗は`!T` (Error Set) で透過的に伝播させる。
  3. **想定された失敗**: 制約違反や仕様上の分岐。正常な値として代数型で返す。\
検討する代数型は次元数の低い順に `bool` → `enum` → `?T` → `union(enum)` or `struct Result {...}` 
- 連続するリソース確保のシステム失敗点では`defer`/`errdefer`ガードを用いる。
- モジュールの非公開API領域で大域脱出のために`!T`を用いることは、それが境界に漏れない限り咎めない。

## trivial

- 同期ログ出力には`std.log.scoped(.name)`を用いる。
- `std.debug.assert`は型で表現できない不変条件に用いる。**入力のバリデーションは不変条件ではない。**
- `error{OutOfMemory}!T`と和解せよ。彼の王国は近づいた。そこら中にあるなら悔い改めよ。
