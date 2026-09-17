## philosophy

### references

1. [Zigの禅](https://ziglang.org/documentation/master/#Zen)を完全継承する。
2. [Zigのスタイルガイド](https://ziglang.org/documentation/master/#Style-Guide)を踏襲するが、衝突する場合はこの文書を優先する。
3. Functional Core, Imperative Shell (FCIS)アーキテクチャを採択する。
4. その実践として[Impureim Sandwich](https://blog.ploeh.dk/2020/03/02/impureim-sandwich/)と[Sans I/O](https://sans-io.readthedocs.io/)に準拠する。

### core complementary concept

FCISやImpureim Sandwichはしばしば、[連続的なIOの扱いの複雑さを封じ込める](https://blog.ploeh.dk/2017/07/10/pure-interactions/)ための木構造(**IO Monad**)に発展する。\
これを自然な形で回避するために次の一点を認める:

- **『システムコールを発行しない状態機械』はCore領域内において純粋である。**

内部フィールドのメモリを変更する(ステートフル状態機械)だとしても、1連の入力に対し演算結果が固定ならば純粋であり、\
不純と判断されるのは、演算結果が一貫しない場合と、システムコールを発行する場合だけだ、と置く。\
この機械はとても強力なので、クライスリ圏の力を借りずともCoreの純粋性を保ち続けることができる。


## naming conventions

- アンダースコアから始まるフィールド名は禁止 (e.g. `some_struct._somefield`) 
  - Zigにプライベートフィールドはない。ないものをあるように扱うのは避ける。
- Shell境界の`*std.Io.Reader`/`*std.Io.Writer`の引数名は`source`/`sink`
  - 具象のReader/Writerに`reader`/`writer`変数名を固定するため([Ref](https://youtu.be/f30PceqQWko?si=TMoQlhtOawuyw7gX&t=1154))。
 
## type and module imports 

- モジュールのトップレベル型は全てファイルの開幕で参照拘束する
  ```zig
  const std = @import("std");
  const Io = std.Io;
  const Allocator = std.mem.Allocator;
  const Engine = @import("core/Engine.zig");
  ```

- ネストされた型は個別に拘束せずトップレベル型を経由して参照する
  ```zig
  pub fn save(sink: *Io.Writer, file: Io.File, stamp: Io.Timestamp) !void {...}
  ```

- 名前空間は各モジュールのトップレベルのみをファイルの開幕で拘束する
  ```zig
  const std = @import("std"); // OK
  const builtin = @import("builtin"); // OK
  const core = @import("core.zig"); // OK
  const time = std.time; // 禁止(シャドーイング防止のため完全修飾する → std.time)
  const path = std.fs.path; // 禁止
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
  - `*const Struct`は標準ライブラリのように構造体のアドレス同一性(`@fieldParentPtr`等)を要求する場合にのみ用いる。
  - C ABI境界では実際の呼び出し規約に従う。

## stack size 

- スタックサイズは64KBを想定して書く
  - 非同期基盤(io_uring等)やファイバー環境を考慮し、1MB/8MBの標準スタックを仮定しない。
  - 4KBを超えるローカル配列をスタックに置かない。
  - 再帰を避ける。末尾再帰指定子も現状は非LLVMバックエンドで動かないため避ける。

## memory allocation

- 基礎: **Grouped Element Thinking** 
  - RAII的な都度の個別確保を避け、作業単位・データ集合ごとにまとめて確保する。
  - `ArenaAllocator` `FixedBufferAllocator` `ArrayList.initCapacity`
  
- 推奨: **Caller-Allocated Buffer** 
  - 可能な限り呼び出し元からバッファを受け取る。
    ```zig
    fn render(buffer: []f32) void
    ```
  
- 次善: **Caller-Passed Allocator** 
  - 動的確保が不可避な場合のみ、引数で明示的に`Allocator`を受け取る。
    ```zig
    fn parse(arena: Allocator) !Ast
    ```
 
- 禁止: **Core領域でのAllocatorフィールド保持**
  - Core構造体はAllocatorを持たない。
  - システムコールを発行しない限り、局所的にはステートフルな状態機械でもOK。**カーネルにだけは飛ばない。**
  
- 適宜: Shell領域でのAllocatorフィールド保持 
  - CLI引数パーサーなど、Shell側の独立したライフタイムを持つ状態機械はアロケータを保持してよい。

## error handling

- [エラーの分類](https://joeduffyblog.com/2016/02/07/the-error-model/#bugs-arent-recoverable-errors)を徹底する:
  1. **不変条件違反(バグ)**: プログラマのミス。`assert`で即座に落とす。
  2. **環境・システムエラー**: IO例外、OOM等。外部要因の失敗は`!T` (Error Set) で透過的に伝播させる。
  3. **想定された失敗**: 制約違反や仕様上の分岐。正常な値として代数型で返す。\
検討する代数型は次元数の低い順に `bool` → `enum` → `?T` → `union(enum)` or `struct Result {...}` 
- 連続するリソース確保のシステム失敗点では `errdefer` ガードを用いる。
- モジュール内のプライベート関数で大域脱出のために`!T`を用いることは、それが境界に漏れない限り咎めない。

## trivial

- 同期ログ出力には`std.log.scoped(.name)`を用いる。
- `std.debug.assert`は型で表現できない不変条件に用いる。**入力のバリデーションは不変条件ではない。**
- `error{OutOfMemory}!T`と和解せよ。彼の王国は近づいた。そこら中にあるなら悔い改めよ。
