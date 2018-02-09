$fulldate = (get-date -f 'yyyy MM dd THHmm')

# Default input AWS credentials for S3
$access = ""
$private = ""
$region = "eu-west-1"

# Set credentials
Set-AWSCredentials -AccessKey $access -SecretKey $private
Set-DefaultAWSRegion $region

function sendmail
{
$subject=$args[0]
$smtpServer = ""
$smtpPort = 587
$username = ""
$password = ""
$from = ""
$to = ""
#$subject = "$time"
$body = ""

$smtp = new-object Net.Mail.SmtpClient($smtpServer, $smtpPort)
$smtp.EnableSsl = $true
$smtp.Credentials = new-object Net.NetworkCredential($username, $password)

$msg = new-object Net.Mail.MailMessage
$msg.From = $from
$msg.To.Add($to)
$msg.Subject = $subject
$msg.Body = $body
#$msg.Attachments.Add($FilenameZip)
$smtp.Send($msg)
}

$S3BUCKET = ""
$tabDir = "D:\Tableau\Tableau Server"
$BACKUPPATH = "D:\Tableau_backup"
$BACKUPTEMP = $BACKUPPATH + "\" + "tmp"
$PATHLOG = $BACKUPPATH + "\" + "log"
$LOGNAME = $fulldate + "." + "log"

#Find latest folder version number in tabDir
$versionDir = Get-ChildItem -Path $tabDir -Directory -name | Where-Object {$_ -like '*.*'} | sort -Descending | select -first 1
$binDir = $tabDir + "\" + $versionDir + "\bin"
$binDirVersion = $tabDir + "\" + $versionDir

#Find installed version number from buildversion.txt in tabDir
$versionFile = Get-Content $binDirVersion\buildversion.txt
$check_match = $versionFile[1] -match 'Version.(\d+)\.(\d+)\.(\d+)'
$version = $matches;
$installedVersion = $version[1] + "." + $version[2] + "." + $version[3]

if ($check_match -eq $False) {
$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Error getting minor version" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
$installedVersion = $versionDir
} 
else {
Write-Output "Tableau version matched by template"
}

$BACKUOFILENAME = "Tableau backup" + " " + "v" + $installedVersion + " " + $fulldate
$EXTENSION = "tsbak"
$BACKUOFILENAMES3 = $BACKUOFILENAME + "." + $EXTENSION
$ARCHIVERETENTION = 5

#Check if log folder exist
If(!(test-path $PATHLOG))
{
New-Item -ItemType Directory -Force -Path $PATHLOG
}

#Check if tmp folder exist
If(!(test-path $BACKUPTEMP))
{
New-Item -ItemType Directory -Force -Path $BACKUPTEMP
}

#Check Tableau Directory exists
$tabDirExists = Test-Path $binDir -PathType Container
if (-Not $tabDirExists) {
    $A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Tableau Directory $tabDir not found! Exiting" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
	sendmail "[$A] Tableau Directory $tabDir not found! Exiting"
    Exit
}

##Check tabadmin exists
  $tabadminPath = "$binDir\tabadmin.exe"
  $tabadminExists = Test-Path $tabadminPath -PathType Leaf
  if (-Not $tabadminExists) {
      $A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Tabadmin.exe file not found! Exiting" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
	  sendmail "[$A] Tabadmin.exe file not found! Exiting"
      Exit
  }

$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Tableau version : $installedVersion" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append

$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Backing up Tableau database..." | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
& $binDir\tabadmin backup $BACKUOFILENAME -t $BACKUPTEMP | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
if ($LastExitCode -ne 0)
{
    $A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Error when creating Tableau database back up" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
	sendmail "[$A] Error when creating Tableau database back up"
}

Import-Module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"
$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] Uploading $BACKUOFILENAME to S3" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
	try {
		Write-S3Object -BucketName $S3BUCKET -File $BACKUOFILENAMES3 | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
		}
	catch {
 	    $last_error = $Error[0]
        "`nError/Exception:`n$Error" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
		sendmail "Error when uploaded file $BACKUOFILENAMES3 to S3"
		  }
$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] File $BACKUOFILENAMES3 uploaded to S3" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append

$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A] List of archives which will be deleted by date:" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
Write-Output "--------------------------------------------------------------------" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
forfiles -p $BACKUPPATH -m *.$EXTENSION /D -$ARCHIVERETENTION /C "cmd /c echo @path" | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
Write-Output "--------------------------------------------------------------------" | Tee-Object -file "$PATHLOG\$LOGNAME" -Appen
$A = (get-date -f 'yyyy-MM-dd HH:mm:ss'); Write-Output "[$A]  Cleaning out old backup files..." | Tee-Object -file "$PATHLOG\$LOGNAME" -Append
forfiles -p $BACKUPPATH -m *.$EXTENSION /D -$ARCHIVERETENTION /C "cmd /c del /f @path"
