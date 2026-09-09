## philosophy

1. [Zigの禅](https://ziglang.org/documentation/master/#Zen)を完全継承する。
2. [Zigのスタイルガイド](https://ziglang.org/documentation/master/#Style-Guide)を踏襲するが、衝突する場合はこの文書を優先する。

## naming conv 

- アンダースコアから始まるフィールド名は禁止 (e.g. `some_struct._somefield`) 
  - Zigにプライベートフィールドはない。これに限らず、ないものをあるように扱うのは避ける。

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
  pub fn readHeader(buffer: []u8, reader: *Io.Reader) !Header {...}
  pub fn save(io: Io, file: Io.File, stamp: Io.Timestamp) !void {...}
  ```

- 名前空間は各ドメインのトップレベルのみをファイルの開幕で拘束する
  ```zig
  const std = @import("std"); // OK
  const builtin = @import("builtin"); // OK
  const core = @import("core.zig"); // まあOKだが、
  const corepkg = @import("core.zig"); // Ghosttyではこう書くことがある
  const core_mod = @import("core.zig"); // こう書く流派もある
  const time = std.time; // 禁止
  const path = std.fs.path; // 禁止
  const table = core.table; // 禁止
  ```
  Zigは変数シャドーイングの扱いが厳しいのでこれを行うと`path`や`time`という単語を使う権利を失う。\
  多少煩雑でもユーティリティ関数はトップレベルから完全修飾しよう。 `std.fs.path.join(...)`

- ファイルスコープ定数と名前空間の拘束とを区別する (使おう)
  ```zig
  const std = @import("std");
  const mylib = @import("mylib");

  const log = std.log.scoped(.engine); // OK
  const assert = std.debug.assert; // OK
  const current_context = mylib.current_context; //OK
  ```

## pass by value

- const参照渡し`fn func(arg: *const Struct)`を**基本的に避ける**
  - 読み取り専用:`fn func(arg: Struct)` 読み書き:`fn func(arg: *Struct)` を使う。
  - Zigでは値渡しパラメーターを自動でメモリ最適な渡し方に変更する最適化がかかる。また値渡しパラメーターは全て`const`である。\
そのため、プログラマが構造体ごとにサイズを計算して自身の判断で`*const`渡しを指定する必要はない。
  - この制約はセマンティクスをもたらし、標準ライブラリでは`*const Struct`パラメーターが構造体のアドレス同一性を求めること(`@fieldParentPtr`アドレス演算を利用する等)の表明として使われる。
  - C ABI境界ではこの指針の限りでなく、実際の呼び出し規約に従うこと。
  
> **_NOTE:_** \
構造体パラメータに適用される`const`は(暗黙のものも含めて)すべて子フィールド・孫フィールドに伝播する。\
また、変更する状態がシステムコールの向こう側(ファイルディスクリプタ)にある場合は普通に値渡しができる。\
感覚をつかむまでは「一度値渡しで書いて、コンパイラに怒られたらポインタ渡しにする」という運用が吉。

## stack size

- (メモリ領域として) 64KBを想定して書く 
  - Zigでは、現在の実行コンテキストがOSスレッドかどうかはIo構造体による。それは固定ではなく、非同期基盤(io_uringなど)と独自ファイバーを使用した実装の場合もある。Io構造体を自分で管理しているとしても、あとから他の実装に差し替えられる利点を捨ててしまうことになるので、1MB/8MBの標準スタックサイズを期待しないこと。
  - スタックを使うのは私たちのローカル変数だけではない。64KB想定のクリアランスはその点でも有効。
  - 再帰を避ける。やむを得ない場合は最小になるように。末尾再帰指定子はよくコンパイルがこける。
  
## heap allocation

- ある単位(作業やデータ集合)に必要なメモリ量があらかじめわかっている時はまとめて確保する
  - RAII言語の哲学(Individual Element Thinking)とは異なる設計哲学(Grouped Element Thinking)に基づく。\
Zigには組み込みのスマートポインタや所有権システムがないが、この設計ではそもそも不要とされる。
  - ArenaやFixed Buffer Allocatorをうまく活用する。通常のアロケーションもなるべく工夫する。
- できる限り外側でのメモリ確保を検討する
  - ループの中で確保しているならその外に出せないか、関数の中で確保しているなら呼び出し元に転嫁できないか考える。
  - 呼び出し元まで転嫁できるなら、スタックで十分かどうかも検討する。
- 良いソフトウェア設計が壊れない範囲で最小の確保回数を目指す
  - 障害点となるシステムコールの中で、メモリ確保は、書く人間の心がけで効果的に減らすことができる。
  - 再利用やピンポンバッファ、リングバッファなど先人の知恵をよく知りよく使う。

> **_NOTE:_** \
コードがRAII的な都度のヒープ確保を行っているときは、設計が間違っていないかを再考するタイミングになる。\
右も左もわからないなら、最初の一歩はきっと`ArrayList.ensureTotalCapacity`から始まる。

## memory principle

- 推奨: Caller-Allocated Buffer
  - 可能な場合、呼び出し元からバッファーを受け取る\
`fn readValue(buffer: []u8) ![]const u8`
- 推奨: Caller-Passed Allocator
  - そうでない場合は、明示的にアロケーターを受け取る。Arenaを要求する時はパラメータ名で示唆する。\
`fn readValue(allocator: Allocator) ![]const u8`\
`fn readValue(arena: Allocator) ![]const u8`
- 適宜: Allocatorのフィールド保持
  - 独立したライフタイムを持つドメインオブジェクトには推奨、その他の場合に非推奨。
- 非推奨: 4KBを越えるスタック配列

## error handling

- error setによる異常系をシステムコールや外部境界の失敗に積極的にゆずる
  - `!T` をIOエラー、OOM等の失敗点として明確にできる。外部境界の例外もドメインエラーではない。
- 単純なドメインエラーではdimensionalityが低い順に`bool` -> `?T` -> `CustomErrorSet!T`で表現する
  - このうちcustom error setだけはerrdeferとスタックトレースの恩恵を受けられる。
  - 基本的には、表現可能な型のうちdimensionalityがもっとも低いものがもっともよい。
- 表現力が必要なドメインエラーは任意の代数的データ型やResult Objectで表現する
  - TigerBeetle、Ghostty、Zigコンパイラでよく出てくる手法。異常系でのリソース解放を正しく書く必要がある:
    1. 失敗点を関数にまとめることでドメインエラーが挟まらないパターン: `union(enum)`の戻り値による代数表現
    2. ドメインエラーにも正規のResult Object (errorsを内包) を返して`deinit`させるパターン: AST解析等
    3. リソースはプログラム開始時に全て確保済みなので失敗点がないパターン: TigerBeetle 北斗神拳は無敵
- 連続するリソース確保の失敗点では`errdefer`ガードを用いる
  - とても便利だが、前述したerror set以外のドメインエラー表現では着火しないため、工夫が必要。
  - スコープ内最後の`try`以降には失敗点がないため`errdefer`を**書いてもコードが生成されない**ことに留意。

>**_NOTE:_**\
基本的には都度適切なパターンを選ぶしかないが、可能なら次のような形を目指したい:\
ドメインオブジェクトの内部(非公開API)ではerror setを使って大域脱出や`errdefer`の恩恵を受け、\
公開APIはそれらを呼び出したあとで適宜代数的データ型やResult Object/Diagnosticなどに丸める。
 
## trivial

- ログ出力には`std.log.scoped(.name)`を用いる。
- `std.debug.assert`は型で表現できない不変条件に用いる。**入力のバリデーションは不変条件ではない。**
- `error{OutOfMemory}!T`と和解せよ。彼の王国は近づいた。そこら中にあるなら悔い改めよ。
