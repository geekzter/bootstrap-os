#region Load Functions
#function Load-Functions {
	Get-ChildItem (Join-Path (Split-Path $Profile –Parent) "Functions") -filter "*.ps1" | ForEach-Object {
		. $_.FullName
	}
#}
#Load-Functions
#endregion
