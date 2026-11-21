# 循环模式与集合字面量

[English](README.md)

`moongrep lint` 默认加载以下四条规则。内建 ID 由 `moonbitlang/` 加上规则名组成。

| 规则 | 匹配的写法 | 建议写法 |
| --- | --- | --- |
| [loop_tuple_unpack](../../internal/rule/lintrules/moonbitlang/loop_tuple_unpack.yaml) | `for pair in rows { let (x, y) = pair; … }` | `for (x, y) in rows { … }` |
| [repeated_classifier](../../internal/rule/lintrules/moonbitlang/repeated_classifier.yaml) | `c == 'a' \|\| c is ('b'..<='f')` | `c is ('a' \| 'b'..<='f')` |
| [iterator_literal](../../internal/rule/lintrules/moonbitlang/iterator_literal.yaml) | `Iter::empty()`、`Iter::singleton(v)`、`[a, b].iter()` | `[\|\|]`、`[\|v\|]`、`[\|a, b\|]` |
| [conditional_array_spread](../../internal/rule/lintrules/moonbitlang/conditional_array_spread.yaml) | 从 `[]` 开始，按条件追加一个元素，再无条件追加一个元素，随后遍历。 | `let items = [..if condition { [optional] }, required]`，之后保留原循环 |

**循环头解构。** 循环体的第一条语句必须解构本轮绑定的二元组。它可以是唯一的循环绑定，也可以是键值遍历中的键或值。原绑定不能有其他用途。嵌套元组、变量和通配符都可以移到循环头，只要名字互不冲突。带类型标注的 `let` 和带循环状态的写法会保留。[示例](tuples.mbt)

**标量的备选模式。** 每个判断都必须读取同一个不可变的 `Char`、`Byte`、定宽整数或 `String` 局部变量。相等比较须使用标准实现，字面量和正向区间须互不重叠。字符串只接受无转义的普通字面量。像 `next() == 'a' || next() == 'b'` 这样的判断可能调用两次 `next`。[示例](classifiers.mbt)

**迭代器字面量。** 构造方法必须是标准的 `Iter` 方法，或对普通数组字面量调用 `Array::iter`。元素仍在创建迭代器时依次求值。已有数组、切片、带展开项的数组和推导式不在匹配范围内。[示例](iterators.mbt)

**数组条件展开。** 新数组只用于两次 `Array::push` 和紧随其后的遍历。改写保留原有类型标注，以及条件和各元素的求值顺序。数组存在别名、容量被读取或条件分支还有其他操作时，保留原写法。[示例](spreads.mbt)

## 运行

在仓库根目录执行以下命令，可在一个文件上运行内建规则，也可以单独指定一份 YAML。默认输出会标出对应源码。

```sh
moon run --target native . -- lint examples/syntax-adoption/tuples.mbt --target wasm
moon run --target native . -- scan examples/syntax-adoption/classifiers.mbt --rule internal/rule/lintrules/moonbitlang/repeated_classifier.yaml --target wasm
```

只需匹配语法时，可以使用[结构查询示例](rules)。若要给有类型检查的规则添加形状或 guard，见 [YAML 规则规范](../../internal/docs/RuleSpec_CN.md#语义规则)。
