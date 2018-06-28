$domain = $args[0]
$location = $args[1]
$dbdomain= $args[2]
$mySqlUser= $args[3]
$mySqlPasswordForUser= $args[4]
# Utility methods
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

# Used to generate SSL password
$alphabet=$NULL;
For ($a=65;$a -le 90;$a++)
{
	$alphabet+=,[char][byte]$a
}

Function GET-Password()
{
	Param(
		[int]$length=10,
		[string[]]$sourcedata
	)
	For ($loop=1; $loop -le $length; $loop++)
	{
		$TempPassword+=($sourcedata | GET-RANDOM)
	}
    return $TempPassword
}

# Initialize variables
$SITENAME="$domain.$location.cloudapp.azure.com"
$DBSITENAME="$dbdomain.$location.cloudapp.azure.com"
echo $SITENAME 

New-Item c:\Temp -type directory

# Download and install JDK and Tomcat
echo "Downloading jdk10..."
$source = "http://download.oracle.com/otn-pub/java/jdk/10.0.1+10/fb4372174a714e6b8c52526dc134031e/jdk-10.0.1_windows-x64_bin.exe"
$destination = "C:\Temp\jdk-10.0.1_windows-x64_bin.exe"
$client = new-object System.Net.WebClient 
$cookie = "oraclelicense=accept-securebackup-cookie"
$client.Headers.Add([System.Net.HttpRequestHeader]::Cookie, $cookie) 
$client.DownloadFile($source,$destination)

echo "Downloading tomcat8..."
$source = "http://apache.mirrors.ionfish.org/tomcat/tomcat-8/v8.5.31/bin/apache-tomcat-8.5.31-windows-x64.zip"
$destination = "C:\Temp\apache-tomcat-8.5.31-windows-x64.zip"
$client = new-object System.Net.WebClient 
$client.DownloadFile($source,$destination)

echo "Installing jdk8..."
$proc1 = Start-Process -FilePath "C:\Temp\jdk-10.0.1_windows-x64_bin.exe" -ArgumentList "/s REBOOT=ReallySuppress" -Wait -PassThru
$proc1.waitForExit()

echo "Setting environment veriable..."
$JDK_PATH="-10.0.1"
[System.Environment]::SetEnvironmentVariable("JAVA_HOME", "c:\Program Files\Java\jdk$JDK_PATH", "Machine")
[System.Environment]::SetEnvironmentVariable("PATH", $Env:Path + ";c:\Program Files\Java\jdk$JDK_PATH\bin", "Machine")

echo "Unzip tomcat8"
Unzip "C:\Temp\apache-tomcat-8.5.31-windows-x64.zip" "C:\"

# Set up SSL access
echo "Generating certificate..."
$SSLKEYPASSWORD=GET-Password -length 12 -sourcedata $alphabet
cd "C:\Program Files\Java\jdk$JDK_PATH\bin\"
.\keytool.exe -genkey -alias tomcat -keyalg RSA -keystore c:\Temp\server.keystore -keysize 2048 -storepass $SSLKEYPASSWORD -keypass $SSLKEYPASSWORD -dname "cn=$SITENAME, ou=shibbolethOU, o=shibbolethO, c=US"

$filedata = [IO.File]::ReadAllText("C:\apache-tomcat-8.5.31\conf\server.xml")
Rename-Item C:\apache-tomcat-8.5.31\conf\server.xml C:\apache-tomcat-8.5.31\conf\server-old.xml
$OriginalString='redirectPort="8443"'
$ReplceString='redirectPort="8443" address="0.0.0.0"'
$filedata=$filedata.Replace($OriginalString,$ReplceString)

$OriginalString="<!-- Define an AJP 1.3 Connector on port 8009 -->"
$ReplaceWith='<Connector port="8443" protocol="org.apache.coyote.http11.Http11Protocol" SSLEnabled="true" maxThreads="150" scheme="https" secure="true"  clientAuth="false" sslProtocol="TLS" address="0.0.0.0" keystoreFile="C:\Temp\server.keystore"' + " keystorePass='$SSLKEYPASSWORD'/>"
$filedata=$filedata.Replace($OriginalString,$ReplaceWith)
[IO.File]::WriteAllText("C:\apache-tomcat-8.5.31\conf\server.xml", $filedata.TrimEnd())

echo "Downloading JSTL..."
$source = "http://central.maven.org/maven2/jstl/jstl/1.2/jstl-1.2.jar"
$destination = "C:\apache-tomcat-8.5.31\lib\jstl-1.2.jar"
$client = new-object System.Net.WebClient 
$client.DownloadFile($source,$destination)

# Download and install Shibboleth IDP
echo "Downloading Shibboleth..."
$source = "https://shibboleth.net/downloads/identity-provider/latest/shibboleth-identity-provider-3.3.3.zip"
$destination = "C:\Temp\shibboleth-identity-provider-3.3.3.zip"
$client = new-object System.Net.WebClient 
$client.DownloadFile($source,$destination)

echo "Unzip shibboleth"
Unzip "C:\Temp\shibboleth-identity-provider-3.3.3.zip" "C:\"

echo "Generate preconfig file"
$newLine= [System.Environment]::NewLine
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.additionalProperties= /conf/ldap.properties, /conf/saml-nameid.properties, /conf/services.properties, /conf/idp.properties" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.sealer.storePassword= $SSLKEYPASSWORD"+ $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.sealer.keyPassword= $SSLKEYPASSWORD" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.signing.key= %{idp.home}/credentials/idp-signing.key" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.signing.cert= %{idp.home}/credentials/idp-signing.crt" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.encryption.key= %{idp.home}/credentials/idp-encryption.key" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.encryption.cert= %{idp.home}/credentials/idp-encryption.crt" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.entityID= https://$SITENAME/idp/shibboleth" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.scope= $SITENAME" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.StorageService= shibboleth.JPAStorageService" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.userStorageKey= shibboleth.consent.AttributeConsentStorageKey" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.userStorageKeyAttribute= %{idp.persistentId.sourceAttribute}" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.allowGlobal= false" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.compareValues= true" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.consent.maxStoredRecords= -1" + $newLine)
[IO.File]::AppendAllText("C:\shibboleth-identity-provider-3.3.3\bin\temp.properties","idp.ui.fallbackLanguages= en,de,fr")
echo "idp.sealer.password = $SSLKEYPASSWORD" >C:\shibboleth-identity-provider-3.3.3\credentials.properties

echo "Running the shibboleth installer..."
$filedata = [IO.File]::ReadAllText("C:\shibboleth-identity-provider-3.3.3\bin\install.bat")
Rename-Item C:\shibboleth-identity-provider-3.3.3\bin\install.bat C:\shibboleth-identity-provider-3.3.3\bin\install-old.bat
$OriginalString="setlocal"
$ReplceString="setlocal`r`nset JAVA_HOME=C:\Program Files\Java\jdk-10.0.1"
$filedata=$filedata.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\shibboleth-identity-provider-3.3.3\bin\install.bat", $filedata.TrimEnd())

cmd.exe /C "C:\shibboleth-identity-provider-3.3.3\bin\install.bat -Didp.src.dir=C:\shibboleth-identity-provider-3.3.3 -Didp.target.dir=C:\opt\shibboleth-idp\ -Didp.merge.properties=C:\shibboleth-identity-provider-3.3.3\bin\temp.properties -Didp.sealer.password=$SSLKEYPASSWORD -Didp.keystore.password=$SSLKEYPASSWORD -Didp.conf.filemode=644 -Didp.host.name=$SITENAME -Didp.scope=$SITENAME"

# Configure Shibboleth IDP
$content = [IO.File]::ReadAllText("C:\opt\shibboleth-idp\metadata\idp-metadata.xml")
Rename-Item C:\opt\shibboleth-idp\metadata\idp-metadata.xml C:\opt\shibboleth-idp\metadata\idp-metadata-old.xml

$OriginalString="https://$SITENAME/idp/profile/Shibboleth/SSO"
$ReplceString="https://$SITENAME"+":8443/idp/profile/Shibboleth/SSO"
$content=$content.Replace($OriginalString,$ReplceString)

$OriginalString="https://$SITENAME/idp/profile/SAML2/POST/SSO"
$ReplceString="https://$SITENAME"+":8443/idp/profile/SAML2/POST/SSO"
$content=$content.Replace($OriginalString,$ReplceString)

$OriginalString="https://$SITENAME/idp/profile/SAML2/POST-SimpleSign/SSO"
$ReplceString="https://$SITENAME"+":8443/idp/profile/SAML2/POST-SimpleSign/SSO"
$content=$content.Replace($OriginalString,$ReplceString)

$OriginalString="https://$SITENAME/idp/profile/SAML2/Redirect/SSO"
$ReplceString="https://$SITENAME"+":8443/idp/profile/SAML2/Redirect/SSO"
$content=$content.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\opt\shibboleth-idp\metadata\idp-metadata.xml", $content.TrimEnd())

echo "Adding application to tomcat8..."
New-Item C:\apache-tomcat-8.5.31\conf\Catalina\localhost -type directory
$appData='<Context docBase="C:\opt\shibboleth-idp\war\idp.war" privileged="true" antiresourcelocking="false" antijarlocking="false" unpackwar="false" swallowoutput="true" />'
[IO.File]::WriteAllText("C:\apache-tomcat-8.5.31\conf\Catalina\localhost\idp.xml", $appData.TrimEnd())

echo "allow access to public"
$content = [IO.File]::ReadAllText("C:\opt\shibboleth-idp\conf\access-control.xml")
Rename-Item C:\opt\shibboleth-idp\conf\access-control.xml C:\opt\shibboleth-idp\conf\access-control-old.xml
$OriginalString="'::1/128'"
$ReplceString="'::1/128', '0.0.0.0/0'"
$content=$content.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\opt\shibboleth-idp\conf\access-control.xml", $content.TrimEnd())
echo "add inbound rule"
cmd.exe /c "netsh advfirewall firewall add rule name="Allow TCP 80,8080,8443" dir=in action=allow edge=yes remoteip=any protocol=TCP localport=80,8080,8443"

# Add beans shibboleth.JPAStorageService, shibboleth.JPAStorageService.EntityManagerFactory, shibboleth.JPAStorageService.JPAVendorAdapter & shibboleth.JPAStorageService.DataSource
$filedata = [IO.File]::ReadAllText("C:\opt\shibboleth-idp\conf\global.xml")
Rename-Item C:\opt\shibboleth-idp\conf\global.xml C:\opt\shibboleth-idp\conf\global-old.xml
$OriginalString='</beans>'
$mySqlPasswordForUserEscaped=[System.Security.SecurityElement]::Escape($mySqlPasswordForUser);
$ReplceString='<bean id="shibboleth.JPAStorageService" class="org.opensaml.storage.impl.JPAStorageService" p:cleanupInterval="%{idp.storage.cleanupInterval:PT10M}" c:factory-ref="shibboleth.JPAStorageService.entityManagerFactory" /> <bean id="shibboleth.JPAStorageService.entityManagerFactory" class="org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean"> <property name="packagesToScan" value="org.opensaml.storage.impl"/> <property name="dataSource" ref="shibboleth.JPAStorageService.DataSource"/> <property name="jpaVendorAdapter" ref="shibboleth.JPAStorageService.JPAVendorAdapter"/> <property name="jpaDialect"> <bean class="org.springframework.orm.jpa.vendor.HibernateJpaDialect" /> </property> </bean> <bean id="shibboleth.JPAStorageService.JPAVendorAdapter" class="org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter"> <property name="database" value="MYSQL" /> </bean> <bean	id="shibboleth.JPAStorageService.DataSource" class="org.apache.tomcat.jdbc.pool.DataSource" destroy-method="close" lazy-init="true" p:driverClassName="com.mysql.jdbc.Driver" p:url="jdbc:mysql://' + $DBSITENAME+ ':3306/idp_db?autoReconnect=true&amp;sessionVariables=wait_timeout=31536000" p:validationQuery="SELECT 1;" p:username="'+ $mySqlUser+'" p:password="' + $mySqlPasswordForUserEscaped+'" /> </beans>'
$filedata=$filedata.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\opt\shibboleth-idp\conf\global.xml", $filedata.TrimEnd())

$filedata = [IO.File]::ReadAllText("C:\opt\shibboleth-idp\conf\idp.properties")
Rename-Item C:\opt\shibboleth-idp\conf\idp.properties C:\opt\shibboleth-idp\conf\idp-old.properties
$OriginalString='#idp.session.StorageService = shibboleth.ClientSessionStorageService'
$ReplceString='idp.session.StorageService = shibboleth.JPAStorageService'
$filedata=$filedata.Replace($OriginalString,$ReplceString)

$OriginalString='#idp.consent.StorageService= shibboleth.JPAStorageService'
$ReplceString='idp.consent.StorageService= shibboleth.JPAStorageService'
$filedata=$filedata.Replace($OriginalString,$ReplceString)

$OriginalString='#idp.replayCache.StorageService = shibboleth.StorageService'
$ReplceString='idp.replayCache.StorageService = shibboleth.JPAStorageService'
$filedata=$filedata.Replace($OriginalString,$ReplceString)

$OriginalString='#idp.artifact.StorageService = shibboleth.StorageService'
$ReplceString='idp.artifact.StorageService = shibboleth.JPAStorageService'
$filedata=$filedata.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\opt\shibboleth-idp\conf\idp.properties", $filedata.TrimEnd())

# Add mysql-connector-java.jar in /tomcat7/lib
$source = "http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.6/mysql-connector-java-5.1.6.jar"
$destination = "C:\apache-tomcat-8.5.31\lib\mysql-connector-java-5.1.6.jar"
$client = new-object System.Net.WebClient 
$cookie = "oraclelicense=accept-securebackup-cookie"
$client.Headers.Add([System.Net.HttpRequestHeader]::Cookie, $cookie) 
$client.DownloadFile($source,$destination)

# Restart Tomcat
echo "restart tomcat"
$filedata = [IO.File]::ReadAllText("C:\apache-tomcat-8.5.31\bin\startup.bat")
Rename-Item C:\apache-tomcat-8.5.31\bin\startup.bat C:\apache-tomcat-8.5.31\bin\startup-old.bat
$OriginalString="setlocal"
$ReplceString="setlocal`r`nset JAVA_HOME=C:\Program Files\Java\jdk-10.0.1"
$filedata=$filedata.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\apache-tomcat-8.5.31\bin\startup.bat", $filedata.TrimEnd())

$filedata = [IO.File]::ReadAllText("C:\apache-tomcat-8.5.31\bin\shutdown.bat")
Rename-Item C:\apache-tomcat-8.5.31\bin\shutdown.bat C:\apache-tomcat-8.5.31\bin\shutdown-old.bat
$OriginalString="setlocal"
$ReplceString="setlocal`r`nset JAVA_HOME=C:\Program Files\Java\jdk-10.0.1"
$filedata=$filedata.Replace($OriginalString,$ReplceString)
[IO.File]::WriteAllText("C:\apache-tomcat-8.5.31\bin\shutdown.bat", $filedata.TrimEnd())

cd C:\apache-tomcat-8.5.31\bin\
Start-Process .\startup.bat