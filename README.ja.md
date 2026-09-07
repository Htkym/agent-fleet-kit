# Codex Fleet Kit

[English](README.md)

この日本語版は、公開された英語の指示書に対応する参考資料です。英語の指示書は静的検証済みですが、英語化後の通常CLIによる実機検証は未実施です。

Codex CLIで調査、実装、検証、独立レビューを分担するための3 Skillと7 Agentです。Rootが依頼を分解して結果を受け入れ、同じ作業ツリーでソースを編集する担当は同時に1人とします。

特定のWindows環境で通常CLIによる実作業を確認しています。すべての環境での動作や、速度・費用・品質の優位を保証するものではありません。OpenAIの公式配布物ではありません。

## SkillとAgent

| Skill | 用途 |
|---|---|
| fleet-orchestrator | 役割の選択、所有範囲の割り当て、検証、独立レビュー、結果回収 |
| evidence-review | 差分と要件に基づくレビュー。場所、重大度、再現条件、未確認点を返す |
| benchmark-lab | 条件を固定した実測比較。正しさ、反復、生データ、測定限界を記録する |

専門SkillはFleetを起動せず、単独でも利用できます。

| Agent | 担当 |
|---|---|
| fleet_explorer | 実装と呼び出し箇所の調査 |
| fleet_researcher | 仕様と既存テストの独立調査 |
| fleet_implementer | 契約が固定された一般実装 |
| fleet_verifier | 実テストと結果の確認 |
| fleet_reviewer | 通常の独立レビュー |
| fleet_worker_fast | 規則と対象が確定した狭い定型変換 |
| fleet_reviewer_critical | 公開契約、状態遷移、寿命、データ整合性などの重要レビュー |

毎回7 Agentを起動する必要はありません。設計判断や想定外の失敗はRootへ戻し、子からの再委譲は行いません。

## 必要な環境

- Windows、PowerShell 7.4以上、Git。
- 実際にAgentを動かす場合は、名前付きAgentに対応したCodex CLIと、利用を許可されたモデル・認証。

ローカル回帰テストとpreview生成には、Codex CLI、ログイン、APIキーは不要です。確認したCLIと制限は[互換性](docs/compatibility.md)に記載しています。

## 生成と確認

リポジトリのルートで実行します。

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

生成物は`.local/build/preview/`、テスト結果は`.local/artifacts/tests.json`、一時作業は`.local/runs/`に保存します。`.local/`全体をGitから除外しています。

モデルの例は[config/model-tiers.example.yaml](config/model-tiers.example.yaml)、役割の対応は[config/routing.yaml](config/routing.yaml)です。例のモデルIDをそのまま利用できるとは限りません。対象のCLIとアカウントで利用できる構成を確認してください。YAMLファイルはJSON互換形式です。

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Preview -ModelTiers config/model-tiers.example.yaml
```

`-Preview`の生成物は`installable=false`です。静的検証の成功は、実効モデル・権限や自動導入の合格を意味しません。

## プロジェクトで使う

生成物の`payload/`から、必要な資産を対象プロジェクトの対応する場所へ配置します。既存ファイルとの衝突は事前に確認してください。生成物を直接編集せず、このリポジトリの原稿を変更して再生成します。

| 生成物内の場所 | 対象プロジェクトの場所 |
|---|---|
| `payload/.agents/skills/<Skill名>/` | `.agents/skills/<Skill名>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

統括とCriticalは、専門Skillがプロジェクトの`.agents/skills/`にあることを前提にしています。プロジェクト設定の例は[config.fragment.toml.template](templates/codex/config.fragment.toml.template)です。既存設定を丸ごと置き換えず、必要な項目の差分を確認して追加します。

対象プロジェクトのルートで明示起動します。依頼文は対象、要件、変更できる範囲を含む具体的な内容に置き換えてください。

```powershell
codex exec --approve-for-me '$fleet-orchestrator を使い、指定した課題を実装、実テスト、独立レビュー、結果回収まで完了してください。実装writerは同時に1つとします。'
codex exec --approve-for-me '$evidence-review を単独で使い、指定した差分と要件をレビューしてください。ソースは変更しないでください。'
codex exec --approve-for-me '$benchmark-lab を単独で使い、指定した2候補を同じ入力で比較し、生データと測定条件を記録してください。'
```

更新、撤回、任意の診断は[運用手順](docs/operations.md)を参照してください。

## 検証範囲

3 Skillの定義を読み込んだ操作と担当作業、7 Agentの名前付き実行、単一writer、実テスト、独立レビュー、Rootへの結果回収、タスク完了をローカルで確認しました。回帰テストはスキーマ、所有権、パス、生成・配置・撤回、保全、失敗時の処理を扱います。GitHub Actionsでは認証不要の回帰・生成・静的検証を実行します。

thread解放、役割ごとのOS強制read-only、全境界試験、暗黙起動、自動導入の全面的な検証は未完了です。親のworkspace-writeが子にも適用されたため、レビューの非編集は役割規約と差分照合で確認しています。12条件比較は未実施で、[比較プロトコル](docs/benchmark-protocol.md)の計画と実測を区別しています。

実行ログ、個人設定の調査記録、ローカル環境のパスを含む証拠は公開ソースに含めません。公開可能な範囲の検証概要は[互換性](docs/compatibility.md)にまとめています。

[開発への参加](CONTRIBUTING.md)・[セキュリティ](SECURITY.md)・[変更履歴](CHANGELOG.md)

## ライセンス

[MIT License](LICENSE)。ライセンス本文の原文は[Open Source Initiative](https://opensource.org/license/mit)を参照してください。
