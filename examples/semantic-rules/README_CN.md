# 数组与迭代器规则

[English](README.md)

这些规则检查推导式写法、结果被丢弃的数组分配，以及对同一迭代器的重复消费。`moongrep lint` 会显示源码位置和建议。内建规则 ID 的前缀是 `moonbitlang/`。

| 规则 | YAML 的 `semantic.check` | 适用条件 |
| --- | --- | --- |
| `prefer_array_comprehension` | `array-comprehension` | 从 `[]` 开始，在循环中为每个入选元素追加一个值，最后返回数组。可写成 `[for x in xs if keep(x) => f(x)]`。累加数组必须没有其他用途，循环中也不能有提前退出或循环状态子句。 |
| `prefer_filter_map_comprehension` | `filter-map-comprehension` | `Array::filter_map` 接受的同步 lambda 不抛出受检错误，并用 `if` 或简单、穷尽的 `Option` 匹配返回 `Some(value)` 或 `None`。带条件的数组推导式可以保留条件和载荷的求值顺序。 |
| `prefer_iter_comprehension` | `iter-comprehension` | 对不可变迭代器绑定的 `it.filter(p).map(f)` 可写成 `[\| for x in it if p(x) => f(x) \|]`。若紧接着收集成数组，可以使用数组推导式。回调必须同步、不会抛出受检错误，移动它们的求值也不能影响行为。 |
| `avoid_collect_for_count` | `collect-count` | `it.collect().length()` 和 `it.to_array().length()` 都只为取长度而消费迭代器，可写成 `it.count()`。 |
| `discarded_array_map` | `discarded-array-map` | `ignore(xs.map(f))` 会构造一个用不到的数组。只需要回调的副作用时可用循环或 `Array::each`。保留 `xs` 和 `f` 的求值，如有需要，在回调内丢弃结果。 |
| `consumed_iterator` | `consumed-iterator` | 相邻两条语句对同一个不可变迭代器绑定调用 `count`、`collect`、`to_array` 或 `last`。如果第二条语句需要重新遍历，就要取得新的迭代器。 |
| `array_map_fusion` | `array-map-fusion` | `xs.map(g).map(f)` 中，两次调用必须都是类型相容的标准 `Array::map`。确认回调的副作用和终止性后，可考虑 `xs.map(x => f(g(x)))`。 |

合并数组上的两次 `map` 会改变不同元素之间的调用顺序。输入有两个元素时，原写法依次执行 `g, g, f, f`，合并后执行 `g, f, g, f`。仅凭类型无法判断回调是否纯，还需保留回调工厂的求值时机。[合并条件](../../internal/semantic_rules/README_CN.md#合并数组的-map-调用)

## 运行与配置

以下命令在 MoonGrep 仓库根目录运行。第一条使用内建规则，第二条只运行示例 YAML 中的规则。

```sh
moon run --target native . -- lint examples/semantic-rules/collections.mbt
moon run --target native . -- scan examples/semantic-rules --rule examples/semantic-rules/custom-count.yaml
```

`semantic.check` 选择类型和符号检查。YAML 可以收紧源码形状或添加正则 guard。下面的示例只对名为 `it` 的迭代器提示使用 `count()`。

```yaml
id: custom_count
description: Prefer count() when only the length is needed.
semantic:
  check: collect-count
  patterns:
    - shape: $(iterator:id).collect().length()
      guard:
        $iterator: '^it$'
```

用 `--disable moonbitlang/array_map_fusion` 禁用单条内建规则，用 `#moongrep.skip` 跳过一个声明。用 `--target wasm` 可以指定被检查代码的后端。[内建 YAML](../../internal/rule/lintrules/moonbitlang) · [规则规范](../../internal/docs/RuleSpec_CN.md#语义规则)
