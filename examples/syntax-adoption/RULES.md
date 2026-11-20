# 已内建的 MoonBit 写法规则

`moongrep lint` 默认加载下面四条规则。终端结果显示规则名、建议和对应源码。单独运行一条时，把其 YAML 文件交给 `scan --rule`。自定义 YAML 可以调整候选形状或增加 guard，匹配仍须通过同一个语义检查。表中 ID 的下划线换成连字符，即对应的 `semantic.check` 名。

| 规则 ID（内建前缀为 `moonbitlang/`） | 识别和建议 | 验证范围 |
| --- | --- | --- |
| `loop_tuple_unpack` | `for pair in rows { let (x, y) = pair; … }` → `for (x, y) in rows { … }`。双元素遍历也可在键或值的位置解构。 | 高亮首句 `let`。IDE 必须确认右侧为二元组，且这是被替换循环绑定的唯一引用。允许嵌套元组、变量和通配符；检查新名字与另一个循环绑定是否冲突。跳过位置靠后的解构、有类型标注的 `let`、记录解构和带循环状态的形式。[YAML](../../internal/rule/lintrules/moonbitlang/loop_tuple_unpack.yaml) |
| `repeated_classifier` | `c == 'a' \|\| c is ('b'..<='f')` → `c is ('a' \| 'b'..<='f')`。同一棵通过检查的 OR 子树只提示一次。 | 对象须为同一个不可变局部绑定，类型为内建字符、字节、定宽整数或字符串。`==` 要解析到标准库的 `Eq::equal` 实现。备选项必须互不重叠，可使用字面量、正向整数/字符区间或已有的备选模式。字符串仅接受无转义的普通字面量。会再次调用函数的表达式、可重绑定变量、下标、绑定模式和浮点值均跳过。[YAML](../../internal/rule/lintrules/moonbitlang/repeated_classifier.yaml) |
| `iterator_literal` | `Iter::empty()` → `[\|\|]`，`Iter::singleton(v)` → `[\|v\|]`，`[a, b].iter()` → `[\|a, b\|]`。 | 检查标准构造函数或 `Array::iter` 的定义，以及调用点的实际迭代器类型。普通元素仍在构造时按顺序求值。对已有数组、切片、含展开项的数组和推导式调用 `.iter()` 均跳过。已有数组推导式中的计算可能产生副作用，转成迭代器推导式会推迟执行。[YAML](../../internal/rule/lintrules/moonbitlang/iterator_literal.yaml) |
| `conditional_array_spread` | 新建空数组，条件成立时压入一个元素，再无条件压入一个元素，紧接着遍历该数组。建议用 `[..if condition { [optional] }, required]` 初始化。 | 高亮初始化和两次追加，保留原类型标注及后续循环。IDE 核对数组只在两处标准 `Array::push` 和循环输入处被使用，并检查元素类型。排除预分配、容量读取、别名、额外分支工作和改变控制流的元素表达式。[YAML](../../internal/rule/lintrules/moonbitlang/conditional_array_spread.yaml) |

## 运行

从仓库根目录使用兼容的 nightly。外层 `--target native` 用于编译 MoonGrep，传给 `lint` 或 `scan` 的 `--target` 选择被分析程序的后端。

```sh
moon run --target native . -- lint examples/syntax-adoption/tuples.mbt --target wasm
moon run --target native . -- scan examples/syntax-adoption/classifiers.mbt \
  --rule internal/rule/lintrules/moonbitlang/repeated_classifier.yaml --target wasm
moon run --target native . -- lint examples/syntax-adoption/iterators.mbt \
  --disable moonbitlang/iterator_literal --target wasm
```

可以用相同命令查看[条件路径列表](spreads.mbt)、[迭代器构造](iterators.mbt)及[应跳过的写法](negative.mbt)。例如，`observe_room` 的调用者能观察数组容量，`keep_pair` 的回调同时接收原始元组。这两处原写法分别需要保留。

```sh
MOON_WORK=off moon -C examples/syntax-adoption test --target wasm,native
moon test tests/ide --target native
```

## 配置

例如，下面的规则只检查名为 `pair` 的单元素循环绑定。把内容保存为 `tuple.yaml` 后，运行 `moongrep scan examples/syntax-adoption/tuples.mbt --rule tuple.yaml --target wasm`。

```yaml
id: unpack_pair
description: Move the first tuple pattern into the loop header.
semantic:
  check: loop-tuple-unpack
  patterns:
    - shape: 'for $(row:id) in $(rows:exp) { let ($(a:pat), $(b:pat)) = $(row:id); $$$rest; $(last:exp) }'
      guard:
        $row: '^pair$'
```

研究目录中的三条调查 YAML 测量语法形状的分布，仍可用于包含旧代码的语料。正式规则和调查查询分别存放在[内建规则目录](../../internal/rule/lintrules/moonbitlang)和[调查目录](rules)。Map 构造、流式插值、词法或字节布局的改写还涉及求值顺序、接收者或协议错误约定，对应案例见[研究报告](README.md)。

[core 月度差异规则](../core-month/README.md)进一步覆盖了可验证的 StringBuilder 插值写入、迭代器遍历和数值比较。

## 发布包复扫

2026-11-20 在七个可构建发布包的原始 ZIP 副本上，只启用本页四个内建 YAML，扫描整个模块，包含测试文件。工具链为 `v0.10.22+c5d6f7c27-nightly`。下表记录通过语义验证的源码位置，末列为每次扫描内去重后的 IDE 请求数。[版本与校验和](corpus.tsv)

| Mooncakes 发布包 | 目标 | 循环解构 | 标量备选 | 迭代器字面量 | 条件展开 | IDE 请求 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Milky2018/moon_skrifa 0.2.0 | wasm | 49 | 5 | 0 | 0 | 123 |
| moonbit-community/yaml 0.0.10 | wasm | 0 | 6 | 0 | 0 | 48 |
| moonbit-community/rabbita 0.17.0 | wasm | 1 | 1 | 0 | 0 | 7 |
| gmlewis/base64 0.16.15 | wasm | 0 | 2 | 0 | 0 | 10 |
| mizchi/bit_diff 0.50.0 | native | 0 | 1 | 0 | 1 | 11 |
| moonbit-community/cmark 0.4.17 | wasm | 1 | 0 | 0 | 0 | 2 |
| moonbit-community/fuzzy_match 0.2.6 | wasm | 0 | 0 | 0 | 0 | 0 |
| **合计** | | **51** | **15** | **0** | **1** | **201** |

七次最终扫描均正常退出，共 67 处，无语义警告。47 处在带测试后缀的文件中。Rabbita 的 `stores.mbt:30` 命中二元组解构；YAML 的 `char_utils.mbt:28` 对五个备选项只报告一次；bit_diff 的 `diff_ops.mbt:730–734` 命中条件路径构造。[Rabbita 源码](https://github.com/moonbit-community/rabbita/blob/4a20586a080bed3d557cbffd698cc26e3a496fd8/rabbita/internal/runtime/stores.mbt#L29-L34) · [YAML 源码](https://assets.mooncakes.io/assets/moonbit-community/yaml@0.0.10/char_utils.mbt.html) · [bit_diff 源码](https://assets.mooncakes.io/assets/mizchi/bit_diff@0.50.0/diff_ops.mbt.html)

字体库曾在并行运行其他测试时出现 IDE 超时，最终结果来自独立缓存的串行复扫。其中 `charmap_test.mbt:317` 的 hover 返回一个含传递依赖类型的二元组。该检查用完整、精确的源码范围确认元数，载荷的打印别名不必在测试文件中可见。

另取旧版 IndexMap 发布源码的三个迭代器构造表达式，放入可编译的最小模块，三处均命中。上轮调查覆盖 17 个包且使用结构查询，其计数衡量的范围不同。[原调查与样本范围](README.md)
