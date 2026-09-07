# Codex Fleet Kit

[English](README.md)

## これは何か

Codex Fleet Kitは、Codex CLIで範囲を限定した作業を分担するためのソースKitです。調査、実装、検証、独立レビューに使う3 Skillと7つの名前付きAgentを提供します。Rootが依頼を分解して範囲を割り当て、結果を統合して受け入れを判断します。

独立した調査、限定的な実装、実テスト、レビューを分ける必要がある作業向けです。常駐スケジューラー、sandbox、OpenAIの公式配布物ではありません。同一worktreeのソース編集者は常に1人にします。

## 使う場面

独立した調査、限定された実装、検証、独立レビューを含む複雑な依頼には`fleet-orchestrator`を使います。根拠付きレビューや実測比較だけが必要なら、専門Skillを単独で使えます。

単純な質問、誤字、Rootが直接完了できる短い密結合修正にはFleetを使いません。子Agentは再委譲しません。

## 含まれるSkillとAgent

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

## 最短の確認手順

リポジトリをcloneしてから、ルートで実行します。

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

回帰テスト、インストール不可のpreview bundle生成、その静的検証を順に実行します。生成物は`.local/build/preview/`、テスト結果は`.local/artifacts/tests.json`、一時作業は`.local/runs/`に保存します。`.local/`全体をGitから除外しています。

モデルの例は[config/model-tiers.example.yaml](config/model-tiers.example.yaml)、役割の対応は[config/routing.yaml](config/routing.yaml)です。例のモデルIDをそのまま利用できるとは限りません。対象のCLIとアカウントで利用できる構成を確認してください。YAMLファイルはJSON互換形式です。

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Preview -ModelTiers config/model-tiers.example.yaml
```

`-Preview`の生成物は`installable=false`です。静的検証の成功は、実効モデル、権限、実機動作、自動導入の合格を意味しません。

## プロジェクトへ追加する

previewを生成してから、`payload/`にある必要な資産だけを対象プロジェクトの対応する場所へコピーします。既存ファイルとの衝突は事前に確認してください。生成物を直接編集せず、このリポジトリの原稿を変更して再生成します。

| 生成物内の場所 | 対象プロジェクトの場所 |
|---|---|
| `payload/.agents/skills/<Skill名>/` | `.agents/skills/<Skill名>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

`fleet-orchestrator`と`fleet_reviewer_critical`は、専門Skillがプロジェクトの`.agents/skills/`にあることを前提にしています。プロジェクト設定の断片例は[config.fragment.toml.template](templates/codex/config.fragment.toml.template)です。既存設定を丸ごと置き換えず、必要な項目の差分を確認して追加します。

対象プロジェクトのルートでSkillを明示起動します。依頼文は、対象、必要な動作、変更を許可するファイル、検証コマンドを含む具体的な内容に置き換えてください。

```powershell
codex exec --approve-for-me '$fleet-orchestrator を使い、指定した課題を実装、実テスト、独立レビュー、結果回収まで完了してください。実装writerは同時に1つとします。'
codex exec --approve-for-me '$evidence-review を単独で使い、指定した差分と要件をレビューしてください。ソースは変更しないでください。'
codex exec --approve-for-me '$benchmark-lab を単独で使い、指定した2候補を同じ入力で比較し、生データと測定条件を記録してください。'
```

更新、撤回、任意の診断は[運用手順](docs/operations.md)を参照してください。

## 安全に使うための注意

- 既存の差分、ステージ済みファイル、未追跡ファイルを保全します。明示的な許可なく破棄や履歴の書き換えをしません。
- 役割のpromptやTOML設定は運用規約であり、OSが強制するセキュリティ境界ではありません。
- ユーザー環境への変更はdry-runから始め、明示的なapply前に提案された差分を確認します。
- 認証情報、個人設定、生ログ、ローカル証跡はGitに含めません。ローカル専用の保存先は`.local/`です。
- 子の完了を受け入れやthread解放と見なしません。Rootが証跡、実際の変更、残存コマンドを確認します。

## 変更後の検証

Kitの正本を変更した後は、リポジトリのルートで次の順序で実行します。

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

テストコマンドはKitの回帰テストを実行します。preview生成はインストール不可のbundleを作り、`verify.ps1`がそのbundleを検査します。Fleetを配置したプロジェクトでは、資産をコピーした後にそのプロジェクトの標準検証コマンドも実行してください。静的検証の成功は、実効モデル、権限、実機動作、自動導入を保証しません。

[開発への参加](CONTRIBUTING.md)・[セキュリティ](SECURITY.md)・[変更履歴](CHANGELOG.md)

## ライセンス

[MIT License](LICENSE)。ライセンス本文の原文は[Open Source Initiative](https://opensource.org/license/mit)を参照してください。
