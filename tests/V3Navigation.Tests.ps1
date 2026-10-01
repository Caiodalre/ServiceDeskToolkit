BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $script:AppText = Get-Content (Join-Path $root "ServiceDeskToolkit-CorporateV3.ps1") -Raw
    $match = [regex]::Match($script:AppText, '(?s)\$xaml = @"\r?\n(.*?)\r?\n"@')
    [xml]$script:LayoutXml = $match.Groups[1].Value
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $script:AppText, [ref]$tokens, [ref]$errors
    )
    $normalizer = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq "ConvertTo-V3SearchText"
    }, $true)
    . ([scriptblock]::Create($normalizer.Extent.Text))
}

Describe "V3 navigation bindings" {
    It "keeps every action handler connected to one unique control" {
        $names = @($script:LayoutXml.SelectNodes('//*[@Name and not(ancestor::*[local-name()="ControlTemplate"])]') | ForEach-Object {
            $_.GetAttribute("Name")
        })
        @($names | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        $handlers = [regex]::Matches(
            $script:AppText,
            '\$window\.FindName\("([^"$]+)"\)\.Add_Click'
        )
        $handlers.Count | Should -BeGreaterThan 0
        foreach ($handler in $handlers) {
            @($names | Where-Object { $_ -eq $handler.Groups[1].Value }).Count |
                Should -Be 1
        }
    }

    It "routes each topic entry to an existing section" {
        $entries = @($script:LayoutXml.SelectNodes('//*[starts-with(@Name,"Nav") and @Tag]'))
        $entries.Count | Should -BeGreaterThan 1
        foreach ($entry in $entries) {
            $tag = $entry.GetAttribute("Tag")
            if ($tag -eq "All") {
                continue
            }
            $section = $script:LayoutXml.SelectSingleNode('//*[@Name="Topic' + $tag + '"]')
            $section | Should -Not -BeNullOrEmpty
            $section.SelectNodes('.//*[local-name()="Button"]').Count |
                Should -BeGreaterThan 0
        }
    }
}

Describe "V3 action search" {
    It "matches typed terms regardless of case, accents and outer whitespace" {
        ConvertTo-V3SearchText "  LICENÇA  " | Should -Be "licenca"
        ConvertTo-V3SearchText "impressão" | Should -Be "impressao"
        ConvertTo-V3SearchText "Conexões de REDE" | Should -Be "conexoes de rede"
        ConvertTo-V3SearchText "   " | Should -Be ""
    }
}
