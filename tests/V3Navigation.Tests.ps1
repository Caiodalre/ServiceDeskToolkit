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
Describe "V3 reading and responsive layout" {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        $reader = [System.Xml.XmlNodeReader]::new($script:LayoutXml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $script:TxtV3Output = $window.FindName("TxtV3Output")
        $script:V3ResultExpanded = $false
        $script:V3CompactLayout = $false
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $script:AppText, [ref]$tokens, [ref]$errors
        )
        foreach ($name in @("Set-V3ResultExpanded", "Update-V3ResponsiveLayout", "Update-V3ActionFilter", "Set-V3Topic", "Set-V3ClipboardText", "Copy-V3OutputToClipboard", "Update-V3SearchResults", "Reset-V3ActionFilters", "Update-V3CompactLayout", "Update-V3ResultSearch", "Move-V3ResultMatch", "Set-V3ResultSearchVisible", "Update-V3ResultSections", "Move-V3ResultSection")) {
            $functionAst = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $name
            }, $true)
            . ([scriptblock]::Create($functionAst.Extent.Text))
        }
    }

    It "restores a resized reading area without losing the report" {
        $grid = $window.FindName("WorkspaceGrid")
        $grid.RowDefinitions[2].Height = [Windows.GridLength]::new(260)
        $grid.RowDefinitions[4].Height = [Windows.GridLength]::new(290)
        $script:TxtV3Output.Text = "Relatório que deve permanecer disponível."
        Set-V3ResultExpanded -Expanded $true
        $window.FindName("ActionsScroll").Visibility | Should -Be "Collapsed"
        Set-V3ResultExpanded -Expanded $false
        $grid.RowDefinitions[2].Height.Value | Should -Be 260
        $grid.RowDefinitions[4].Height.Value | Should -Be 290
        $window.FindName("ActionsScroll").Visibility | Should -Be "Visible"
        $script:TxtV3Output.Text | Should -Be "Relatório que deve permanecer disponível."
    }

    It "finds an action outside the current theme while preserving the search and report" {
        $window.FindName("SearchActions").Text = "licença"
        $script:TxtV3Output.Text = "Resultado anterior"
        Set-V3Topic -Topic Network
        $window.FindName("NoActions").Visibility | Should -Be "Visible"
        Set-V3Topic -Topic All
        $window.FindName("NoActions").Visibility | Should -Be "Collapsed"
        $window.FindName("SearchActions").Text | Should -Be "licença"
        $script:TxtV3Output.Text | Should -Be "Resultado anterior"
    }

    It "reveals matching actions when a search changes during expanded reading" {
        Set-V3Topic -Topic All
        $script:TxtV3Output.Text = "Resultado preservado"
        Set-V3ResultExpanded -Expanded $true
        $window.FindName("SearchActions").Text = "licença"
        Update-V3SearchResults
        $window.FindName("ActionsScroll").Visibility | Should -Be "Visible"
        $window.FindName("NoActions").Visibility | Should -Be "Collapsed"
        $window.FindName("SearchActions").Text | Should -Be "licença"
        $script:TxtV3Output.Text | Should -Be "Resultado preservado"
    }
    It "combines maintenance filtering with the theme and preserves the report" {
        $window.FindName("SearchActions").Clear()
        $window.FindName("ActionKind").SelectedIndex = 2
        $script:TxtV3Output.Text = "Relatório preservado ao filtrar"
        Set-V3Topic -Topic Network
        $groups = @($window.FindName("TopicNetwork").Children | Where-Object {
            $_ -is [Windows.Controls.StackPanel] -and $_.Tag -eq "ActionsGroup"
        })
        ($groups | Where-Object Uid -eq "Consultation").Visibility | Should -Be "Collapsed"
        ($groups | Where-Object Uid -eq "Maintenance").Visibility | Should -Be "Visible"
        $script:TxtV3Output.Text | Should -Be "Relatório preservado ao filtrar"
        $window.FindName("ActionKind").SelectedIndex = 0
        Update-V3ActionFilter
        ($groups | Where-Object Uid -eq "Consultation").Visibility | Should -Be "Visible"
    }

    It "shows no results when the selected theme has no maintenance actions" {
        $window.FindName("SearchActions").Clear()
        $window.FindName("ActionKind").SelectedIndex = 2
        Set-V3Topic -Topic Overview
        $window.FindName("NoActions").Visibility | Should -Be "Visible"
        $window.FindName("NoActions").Text | Should -BeLike "*tipo de ação*"
        $window.FindName("ActionKind").SelectedIndex = 0
        Update-V3ActionFilter
        $window.FindName("NoActions").Visibility | Should -Be "Collapsed"
    }
    It "restores all actions from an empty filtered view without clearing the report" {
        $script:TxtV3Output.Text = "Diagnóstico anterior"
        $window.FindName("ActionKind").SelectedIndex = 1
        $window.FindName("SearchActions").Text = "zzzz-inexistente"
        Set-V3Topic -Topic Windows
        $window.FindName("BtnV3ResetFilters").Visibility | Should -Be "Visible"
        Reset-V3ActionFilters
        $script:V3SelectedTopic | Should -Be "All"
        $window.FindName("ActionKind").SelectedIndex | Should -Be 0
        $window.FindName("SearchActions").Text | Should -Be ""
        $window.FindName("NoActions").Visibility | Should -Be "Collapsed"
        $window.FindName("BtnV3ResetFilters").Visibility | Should -Be "Collapsed"
        $script:TxtV3Output.Text | Should -Be "Diagnóstico anterior"
    }
    It "keeps the reading area inside a short viewport and restores the full header" {
        $surface = $window.Content
        $window.FindName("SearchActions").Clear()
        Set-V3Topic -Topic Printers
        $script:TxtV3Output.Text = "Relatório preservado durante redimensionamento"
        foreach ($height in @(450, 760)) {
            $surface.Width = 910
            $surface.Height = $height
            $surface.Measure([Windows.Size]::new(910, $height))
            $surface.Arrange([Windows.Rect]::new(0, 0, 910, $height))
            $surface.UpdateLayout()
            Update-V3CompactLayout
            $surface.Measure([Windows.Size]::new(910, $height))
            $surface.Arrange([Windows.Rect]::new(0, 0, 910, $height))
            $surface.UpdateLayout()
            $grid = $window.FindName("WorkspaceGrid")
            ($grid.ActualHeight + $grid.Margin.Top + $grid.Margin.Bottom) | Should -BeLessOrEqual $height
            $window.FindName("TxtV3Output").ActualHeight | Should -BeGreaterThan 60
            $window.FindName("WorkspaceFooter").Visibility | Should -Be $(if ($height -eq 450) { "Collapsed" } else { "Visible" })
            $script:TxtV3Output.Text | Should -Be "Relatório preservado durante redimensionamento"
        }
    }
    It "copies the report without appending feedback to its contents" {
        Mock Set-V3ClipboardText {}
        $script:TxtV3Output.Text = "Relatório original"
        Copy-V3OutputToClipboard
        Should -Invoke Set-V3ClipboardText -Times 1 -ParameterFilter { $Text -eq "Relatório original" }
        $script:TxtV3Output.Text | Should -Be "Relatório original"
        $window.FindName("ResultStatus").Text | Should -BeLike "Resultado copiado*"
    }

    It "finds literal report text regardless of case and cycles in both directions" {
        $original = "[8] Windows Temp`r`nTEMP: exemplo.txt`r`nFim Temp"
        $script:TxtV3Output.Text = $original
        $window.FindName("SearchResult").Text = "temp"
        Update-V3ResultSearch
        $script:V3ResultMatches.Count | Should -Be 3
        $script:TxtV3Output.SelectionStart | Should -Be 12
        $window.FindName("ResultMatchStatus").Text | Should -Be "1 de 3"
        Move-V3ResultMatch -Direction -1
        $window.FindName("ResultMatchStatus").Text | Should -Be "3 de 3"
        Move-V3ResultMatch -Direction 1
        $window.FindName("ResultMatchStatus").Text | Should -Be "1 de 3"
        $window.FindName("SearchResult").Text = ".txt"
        Update-V3ResultSearch
        $script:V3ResultMatches.Count | Should -Be 1
        $script:TxtV3Output.SelectedText | Should -Be ".txt"
        $script:TxtV3Output.Text | Should -Be $original
    }

    It "jumps to report sections instead of summary rows and preserves the report" {
        $original = "INDICE`r`n[8] Windows Temp | 2 arquivos | 1 MB`r`n[22] Lixeira | 1 arquivo`r`n`r`n[8] Windows Temp`r`nPassos dos temporários.`r`n`r`n[22] Lixeira`r`nPassos da lixeira."
        $script:TxtV3Output.Text = $original
        Update-V3ResultSections
        $picker = $window.FindName("ResultSections")
        $picker.Items.Count | Should -Be 3
        $picker.Visibility | Should -Be "Visible"
        Set-V3ResultSearchVisible -Visible $true
        $picker.SelectedIndex = 2
        Move-V3ResultSection
        $script:TxtV3Output.SelectionStart | Should -Be $original.LastIndexOf('[22] Lixeira')
        $script:TxtV3Output.SelectedText | Should -Be '[22] Lixeira'
        $script:V3ResultExpanded | Should -BeTrue
        $window.FindName("ResultSearchPanel").Visibility | Should -Be "Collapsed"
        $script:TxtV3Output.Text | Should -Be $original
        Set-V3ResultExpanded -Expanded $false
    }

    It "removes previous section targets when a new unnumbered report is displayed" {
        $script:TxtV3Output.Text = "[1] Primeiro relatório`nConteúdo"
        Update-V3ResultSections
        $window.FindName("ResultSections").Items.Count | Should -Be 2
        $script:TxtV3Output.Text = "Outro relatório sem seções numeradas"
        Update-V3ResultSections
        $window.FindName("ResultSections").Visibility | Should -Be "Collapsed"
        $window.FindName("ResultSections").Items.Count | Should -Be 0
        Move-V3ResultSection
        $script:TxtV3Output.Text | Should -Be "Outro relatório sem seções numeradas"
    }

    It "disables navigation for absent or empty terms and recalculates for a new report" {
        $window.FindName("SearchResult").Text = "Lixeira"
        $script:TxtV3Output.Text = "Lixeira: conferir itens"
        Update-V3ResultSearch
        $script:V3ResultMatches.Count | Should -Be 1
        $script:TxtV3Output.Text = "Outro diagnóstico"
        Update-V3ResultSearch
        $window.FindName("ResultMatchStatus").Text | Should -Be "Nenhuma ocorrência"
        $window.FindName("BtnV3NextMatch").IsEnabled | Should -BeFalse
        Move-V3ResultMatch -Direction 1
        $script:TxtV3Output.Text | Should -Be "Outro diagnóstico"
        $window.FindName("SearchResult").Clear()
        Update-V3ResultSearch
        $window.FindName("ResultMatchStatus").Text | Should -Be "Digite um texto"
        $window.FindName("BtnV3PreviousMatch").IsEnabled | Should -BeFalse
    }

    It "opens report search with a usable reading area in a short window" {
        $script:TxtV3Output.Text = "Plano de espaço preservado"
        $surface = $window.Content
        $surface.Width = 820
        $surface.Height = 450
        $surface.Measure([Windows.Size]::new(820, 450))
        $surface.Arrange([Windows.Rect]::new(0, 0, 820, 450))
        $surface.UpdateLayout()
        Update-V3CompactLayout
        Set-V3ResultSearchVisible -Visible $true
        $surface.UpdateLayout()
        $window.FindName("TxtV3Output").ActualHeight | Should -BeGreaterThan 100
        $window.FindName("SearchResult").ActualWidth | Should -BeGreaterThan 80
        $window.FindName("ResultSearchPanel").Visibility | Should -Be "Visible"
        Set-V3ResultSearchVisible -Visible $false
        $window.FindName("ResultSearchPanel").Visibility | Should -Be "Collapsed"
        $script:TxtV3Output.Text | Should -Be "Plano de espaço preservado"
        Set-V3ResultExpanded -Expanded $false
    }

    It "preserves the report when the clipboard is unavailable" {
        Mock Set-V3ClipboardText { throw "Clipboard busy" }
        $script:TxtV3Output.Text = "Relatório para tentar novamente"
        Copy-V3OutputToClipboard
        $script:TxtV3Output.Text | Should -Be "Relatório para tentar novamente"
        $window.FindName("ResultStatus").Text | Should -Be "Cópia indisponível. Tente novamente."
    }
    It "uses one card column in a narrow window and two in a wider window" {
        $window.FindName("SearchActions").Clear()
        Set-V3Topic -Topic Network
        foreach ($width in @(820, 1180)) {
            $surface = $window.Content
            $surface.Width = $width
            $surface.Height = 640
            $surface.Measure([Windows.Size]::new($width, 640))
            $surface.Arrange([Windows.Rect]::new(0, 0, $width, 640))
            $surface.UpdateLayout()
            Update-V3ResponsiveLayout
            $groups = @($window.FindName("TopicNetwork").Children | Where-Object {
                $_ -is [Windows.Controls.StackPanel] -and $_.Tag -eq "ActionsGroup"
            })
            $cards = @($groups[0].Children | Where-Object { $_ -is [Windows.Controls.Primitives.UniformGrid] })
            $cards[0].Columns | Should -Be $(if ($width -eq 820) { 1 } else { 2 })
        }
    }
}
