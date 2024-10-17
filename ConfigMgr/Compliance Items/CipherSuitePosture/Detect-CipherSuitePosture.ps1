#####################################
# Detect-CipherSuitePosture.ps1
# Author(s): Sean Huggans
$ScriptVersion = "24.10.17.2"
######################################
# Variables
#############################
[string[]]$CipherSuitesToDisable = "TLS_RSA_WITH_3DES_EDE_CBC_SHA"

$CipherSuiteCompliance = $true
foreach ($TLSCipherSuite in $CipherSuitesToDisable) {
    Try {
        if ([array]$(Get-TlsCipherSuite -ErrorAction Stop).name -contains $TLSCipherSuite) {
            $CipherSuiteCompliance = $false
        }
    } catch {
        $CipherSuiteCompliance = $false
    }
}

return $CipherSuiteCompliance