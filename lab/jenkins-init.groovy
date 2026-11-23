import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.UserRemoteConfig
import hudson.slaves.EnvironmentVariablesNodeProperty
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition

def jenkins = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
if (realm.getUser('lab-admin') == null) {
    realm.createAccount('lab-admin', new File(jenkins.rootDir, 'local-admin.pass').text.trim())
}
jenkins.setSecurityRealm(realm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
jenkins.setAuthorizationStrategy(strategy)
jenkins.setLabelString('docker')
jenkins.setNumExecutors(1)
def nodeEnvironment = jenkins.globalNodeProperties.get(EnvironmentVariablesNodeProperty.class)
if (nodeEnvironment == null) {
    nodeEnvironment = new EnvironmentVariablesNodeProperty()
    jenkins.globalNodeProperties.add(nodeEnvironment)
}
nodeEnvironment.envVars.put('RELEASE_TARGET', 'minikube')
nodeEnvironment.envVars.put('ACEEST_CONTEXT', 'aceest-prayogshala')
[Assignment1: 'assignment-1', Assignment2: 'main'].each { name, branch ->
    def job = jenkins.getItem(name) ?: jenkins.createProject(WorkflowJob.class, name)
    def scm = new GitSCM(
        [new UserRemoteConfig('https://github.com/kaithsuku/aceest-fitness-devops.git', null, null, null)],
        [new BranchSpec("*/${branch}")], null, null, []
    )
    job.definition = new CpsScmFlowDefinition(scm, 'Jenkinsfile')
    job.save()
}
jenkins.save()
