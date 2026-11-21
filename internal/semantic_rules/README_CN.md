# 语义规则指南

[English](README.md)

`moongrep lint <path>` 默认加载 63 条语义规则。用 `moongrep scan <path> --rule <file>` 指定一份 YAML 可以单独运行一条规则。默认输出包含规则 ID、建议和命中的源码。

| 规则指南 | 涵盖的写法 |
| --- | --- |
| [数组与迭代器](../../examples/semantic-rules/README_CN.md) | 构造推导式、直接计数、识别对已消费迭代器的再次遍历。 |
| [集合、Option 与 Result](../../examples/semantic-theorems/README_CN.md) | 合并过滤与终结操作、组合回调、简化构造函数和恒等变换。 |
| [标准库写法](../../examples/stdlib-patterns/README_CN.md) | 成员判断与判空、手写 Option 和 Result 操作、短路循环与 ASCII 谓词。 |
| [循环模式与集合字面量](../../examples/syntax-adoption/README_CN.md) | 在循环头解构二元组、合并标量备选模式、使用迭代器字面量和数组条件展开。 |
| [数值、遍历与文本](../../examples/core-month/README_CN.md) | 数值判断与极值、直接遍历、省略切片终点和流式插值。另含可选的人工审查查询。 |

YAML 的形状和 guard 先从源码中筛出候选，各条规则再按需查询对应位置的类型、定义或绑定引用。自定义 YAML 可以收紧内建检查的匹配范围。[YAML 规则规范](../docs/RuleSpec_CN.md#语义规则) · [IDE 查询细节](../ide/README.md)

## 合并数组的 map 调用

`array_map_fusion` 匹配连续两次标准 `Array::map` 调用，每次都只有一个位置参数。对于 `xs.map(g).map(f)`，接收者和两次结果的类型须分别为 `Array[A]`、`Array[B]` 和 `Array[C]`，回调类型须为相容的 `A → B` 与 `B → C`，同时都是同步且不会抛出受检错误的函数。

可考虑写成 `xs.map(x => f(g(x)))`。两个回调都纯且会终止时，一次遍历即可得到相同的元素。若回调有副作用，要注意调用顺序。原写法先对所有元素调用 `g`，再开始调用 `f`。合并后每个元素执行完 `g` 就会执行 `f`。回调工厂本身的求值时机和次数也需要保留。

在仓库根目录运行以下命令可查看类型变化和跳过某个候选的原因。通过类型检查的候选标记为 `requires_review`，加 `--json` 可以查看结构化输出。

```sh
moon run --target native . -- map-fusion tools/map-fusion/fixture
```
