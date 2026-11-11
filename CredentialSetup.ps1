#requires -Version 5.1
param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$credentialPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkAutoLogin\credential.xml'
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="校园网自动登录 — 保存本机凭据" Width="500" Height="400" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Topmost="True" FontFamily="Microsoft YaHei" FontSize="14">
<StackPanel Margin="25">
<TextBlock Text="保存校园网登录信息" FontSize="22" Margin="0,0,0,12"/>
<TextBlock Text="仅用于 Fzdxkjy-web 和认证服务器 10.20.21.2。密码以 Windows DPAPI 加密保存到本机。" TextWrapping="Wrap" Margin="0,0,0,14"/>
<TextBlock Text="校园网账号"/>
<TextBox x:Name="Account" Height="30" Margin="0,4,0,10"/>
<TextBlock Text="校园网密码"/>
<PasswordBox x:Name="Secret" Height="30" Margin="0,4,0,12"/>
<TextBlock x:Name="Status" Text="此窗口只保存加密凭据。保存成功后请关闭窗口，再运行 3-Enable.cmd。" TextWrapping="Wrap" Height="40" FontSize="12"/>
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
<Button x:Name="Close" Content="关闭" Width="75" Height="32" Margin="0,0,10,0"/>
<Button x:Name="Save" Content="保存到本机" Width="120" Height="32" IsDefault="True"/>
</StackPanel>
</StackPanel></Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$accountBox=$window.FindName('Account')
$secretBox=$window.FindName('Secret')
$status=$window.FindName('Status')
$save=$window.FindName('Save')
$window.FindName('Close').Add_Click({$window.Close()})
$save.Add_Click({
    try {
        if([string]::IsNullOrWhiteSpace($accountBox.Text) -or $secretBox.SecurePassword.Length -eq 0){$status.Text='请填写账号和密码。';return}
        $credential=New-Object Management.Automation.PSCredential($accountBox.Text.Trim(),$secretBox.SecurePassword)
        $credential | Export-Clixml -LiteralPath $credentialPath -Encoding UTF8
        $credential=$null
        $secretBox.Clear()
        $save.IsEnabled=$false
        $accountBox.IsEnabled=$false
        $secretBox.IsEnabled=$false
        $status.Text='加密凭据已保存。请关闭窗口，再运行 3-Enable.cmd。'
    } catch {$status.Text='保存失败，请保留窗口并告诉助手；无需发送密码。'}
})
if($ValidateOnly){'Credential dialog validated; no credential written.';exit 0}
$window.Add_ContentRendered({[void]$window.Activate();[void]$accountBox.Focus()})
[void]$window.ShowDialog()
