# Fleet Kit

[English](README.md)

Fleet Kitは、Codex CLIとGitHub Copilot CLIで調査、実装、検証、独立レビューを分担するための3つのSkillと7つの役割を提供します。Rootと呼ぶ親Agentが作業範囲を割り当て、変更を統合し、要件を満たしたかを判断します。

同じworktreeでソースを編集するAgentは常に1つに限定し、子Agentは再委譲しません。Fleet Kitは手順とツールのセットであり、スケジューラーやOSのsandboxではありません。OpenAIやGitHubの公式製品ではありません。

## Pluginを導入する

[v0.1.1のリリース](https://github.com/Htkym/agent-fleet-kit/releases/tag/v0.1.1)から`fleet-kit-plugins-0.1.1.zip`をダウンロードし、隠しディレクトリの`.agents`と`.github`を含めて全体を展開します。GitHubの「Source code」は開発用ソースなので、導入には添付のPlugin用ZIPを使ってください。チェックサムは同じリリースの`SHA256SUMS`にあります。

展開先のうち、`plugins/`と`package-manifest.json`があるディレクトリで、利用するCLIのコマンドを実行します。

### Copilot CLI

```powershell
copilot plugin install .\plugins\fleet-copilot
copilot plugin list
```

### Codex CLI

```powershell
codex plugin marketplace add .
codex plugin add fleet-codex@fleet-kit-codex
codex plugin list --json
```

| Plugin | 含まれるもの | モデルの選択 |
|---|---|---|
| `fleet-copilot` | 3つのSkillと7つのネイティブMarkdown Agent定義 | Copilotの設定を継承する |
| `fleet-codex` | 3つのSkillと、Skillのリソースとして同梱した7役割の契約 | 利用を許可されたセッションのモデルを使い、モデル設定は追加しない |

Codex Pluginは名前付きTOML Agentを登録しません。orchestratorが同梱の役割契約を読み、対応する子Agent起動ツールへ渡します。Copilotでは`fleet-copilot:fleet_explorer`のような名前で表示される場合があるため、実際に認識された名前を使います。

導入後は、作業対象のプロジェクトでCLIの新しいセッションを開始します。読み込まれたSkillと、Copilotの場合はAgent定義も確認してください。プロジェクトや個人設定に同名のSkillがある場合は、どの定義を使うかを確認してから依頼します。更新、削除、実機確認の記録は[Pluginの手順](docs/plugins.md)にあります。

## Codexのオーケストレーション設定

RootにはAstra Lowを使います。Codex設定のトップレベルに`model = "gpt-6-astra"`と`model_reasoning_effort = "low"`を指定してください。Pluginの導入だけでは設定は追加されず、実行中のセッションも切り替わりません。

子Agentには、調査と検証でTerra medium、実装でTerra high、レビューでSol high、Worker FastでLuna mediumを指定する方針です。実際に選べるモデルと起動ツールの対応範囲に従います。Worker Fastは規則と結果が決まった定型変更に限定します。Rootは根拠がある場合にmediumやhighへ上げ、問題が解消したらlowへ戻します。

通常は独立した子タスクを最大3つまで並行して進め、実際のセッション上限に従います。ソースを編集するAgentはworktreeごとに1つとし、子Agentは再委譲しません。提案している4スレッドの上限はRootを含まず、別途Codex側の設定が必要です。この方針での実行結果や費用、品質の改善は未検証です。Copilotは引き続きCopilot側のモデル設定を使います。

## Skillを使う

Codexでは`fleet-codex`の`$fleet-orchestrator`を、Copilotでは`fleet-copilot`の`fleet-orchestrator` Skillを指定します。依頼には要件、変更を許可するファイル、検証コマンドを含めてください。次のパスとコマンドは、対象プロジェクトに合わせて置き換えます。

```text
導入済みのFleet Pluginにあるfleet-orchestrator Skillを使ってください。
src/eligibility.cjsで「5年以上」を対象とする境界条件を修正してください。
変更してよいソースはこのファイルだけです。既存の入力検証は維持してください。
node --test tests/eligibility.test.cjsを実行し、独立レビューを受けたうえで、
実際のテスト結果と残る制限を報告してください。
```

## 使う場面

独立した調査、限定された実装、検証、独立レビューを含む複雑な依頼には`fleet-orchestrator`を使います。根拠付きレビューや実測比較だけが必要なら、専門Skillを単独で使えます。

単純な質問や誤字の修正など、親Agentが直接完了できる小さな作業は分担しません。

## Skillと役割

| Skill | 用途 |
|---|---|
| fleet-orchestrator | 役割の選択、所有範囲の割り当て、検証、独立レビュー、結果回収 |
| evidence-review | 差分と要件に基づくレビュー。場所、重大度、再現条件、未確認点を返す |
| benchmark-lab | 条件を固定した実測比較。正しさ、反復、生データ、測定限界を記録する |

専門SkillはFleetを起動せず、単独でも利用できます。

| 役割 | 担当 |
|---|---|
| fleet_explorer | 実装と呼び出し箇所の調査 |
| fleet_researcher | 仕様と既存テストの独立調査 |
| fleet_implementer | 要件と担当範囲が決まった実装 |
| fleet_verifier | 実テストと結果の確認 |
| fleet_reviewer | 通常の独立レビュー |
| fleet_worker_fast | 規則と対象が決まった定型的な変更 |
| fleet_reviewer_critical | 公開契約、状態遷移、寿命、データ整合性などの重要レビュー |

毎回7つの役割をすべて起動する必要はありません。設計判断や想定外の失敗は親Agentへ戻します。

## 必要な環境と確認範囲

Pluginの利用には、ネイティブPluginに対応した各CLI、認証、利用を許可されたモデルが必要です。実機確認では、Windows上のCodex CLI `0.153.4`とCopilot CLI `1.0.84-1`を使用しました。これらは確認したバージョンであり、動作を保証する最低バージョンではありません。

9月7日の記録では、Copilotの7役割の実行と単独の実測比較を確認しています。Codex Pluginは導入とSkillの検出までを確認し、推論は実行していません。従来のCodexプロジェクト配置版には別の実機記録があります。詳しい範囲は[互換性](docs/compatibility.md)と[Pluginの実機記録](docs/plugins.md#local-runtime-observations-2026-09-07)を参照してください。

ソースKitの生成とテストには、Windows、PowerShell 7.4以上、Gitが必要です。標準の検証にはCLIへのログインやAPIキーは不要です。認証を伴う実機テストは、明示的に指定した場合だけ実行します。

## ソースからPluginを生成する

ソースリポジトリのルートで実行します。

```powershell
pwsh -NoProfile -File scripts/package.ps1
pwsh -NoProfile -File scripts/package.ps1 -VerifyOnly
```

配布物一式は`.local/build/plugins/`に生成されます。上記のPlugin導入コマンドを使う場合は、このディレクトリへ移動してください。パッケージ生成ではPluginの導入や個人設定の変更は行いません。生成物を直接編集せず、ソースを変更して再生成します。

## プロジェクト内に配置するファイルを生成する

以下は、Pluginの代わりにプロジェクト内でファイルを管理する場合の手順です。

### Codexのプロジェクト配置版

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

### Codex用ファイルをコピーする

previewを生成してから、`payload/`にある必要な資産だけを対象プロジェクトの対応する場所へコピーします。既存ファイルとの衝突は事前に確認してください。生成物を直接編集せず、このリポジトリの原稿を変更して再生成します。

| 生成物内の場所 | 対象プロジェクトの場所 |
|---|---|
| `payload/.agents/skills/<Skill名>/` | `.agents/skills/<Skill名>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

`fleet-orchestrator`と`fleet_reviewer_critical`は、専門Skillがプロジェクトの`.agents/skills/`にあることを前提にしています。プロジェクト設定の断片例は[config.fragment.toml.template](templates/codex/config.fragment.toml.template)です。既存設定を丸ごと置き換えず、必要な項目の差分を確認して追加します。

対象プロジェクトでCodexの新しいセッションを開始し、プロジェクトのSkillを指定します。上記の使用例と同様に、要件、変更を許可するファイル、検証コマンドを含めてください。モデル設定とTOML設定はこのプロジェクト配置版のものであり、どちらのPluginでも導入しません。更新や任意の診断は[運用手順](docs/operations.md)を参照してください。

### Copilotのプロジェクト配置版

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Target Copilot -Preview
pwsh -NoProfile -File scripts/verify.ps1 -Bundle .local/build/copilot-preview
```

`.local/build/copilot-preview/payload/.github/`から必要な`skills`と`agents`を、Skillの参照資料やスキーマも含めてプロジェクトの`.github/`へコピーします。既存ファイルとの衝突は事前に確認してください。Copilotは`.agents/skills`も検出するため、Codex版の同名Skillがある場合は、どの定義を使うかを確認します。モデルはCopilotの設定を継承します。詳しくは[Copilotの配置・読み込み確認手順](docs/copilot-cli.md)を参照してください。

どちらのpreviewも`installable=false`のため、Kitの従来のインストーラーでは通常の適用を拒否します。この制限とネイティブPluginの導入は別の仕組みです。

## 安全に使うための注意

- 既存の差分、ステージ済みファイル、未追跡ファイルを保全します。明示的な許可なく破棄や履歴の書き換えをしません。
- 役割の指示やTOML設定は運用上の取り決めであり、OSが強制するセキュリティ境界ではありません。
- ユーザー環境を変更する前に、dry-runで差分を確認してから適用します。
- 認証情報、個人設定、生ログ、ローカル証跡はGitに含めません。ローカル専用の保存先は`.local/`です。
- 子Agentの完了だけで受け入れやスレッドの解放を判断しません。親Agentが実行の証拠、実際の変更、実行中のコマンドを確認します。

## 変更後の検証

ソースを変更した後は、[開発者向けの検証手順](CONTRIBUTING.md#changes-and-checks)をすべて実行します。回帰テスト、両CLI向けのpreview、Pluginパッケージが対象で、Windows CIでも同じ検証を実行します。Fleetを配置したプロジェクトでは、更新後にそのプロジェクトの標準検証も実行してください。静的検証の成功は、実機動作やOSによる権限制御の確認を意味しません。

[開発への参加](CONTRIBUTING.md)・[セキュリティ](SECURITY.md)・[変更履歴](CHANGELOG.md)

## ライセンス

[MIT License](LICENSE)。ライセンス本文の原文は[Open Source Initiative](https://opensource.org/license/mit)を参照してください。
