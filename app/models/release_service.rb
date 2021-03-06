# frozen_string_literal: true
class ReleaseService
  def initialize(project)
    @project = project
  end

  def release(attrs = {})
    release = @project.releases.create(attrs)
    if release.persisted?
      push_tag_to_git_repository(release.version, release.commit)
      ensure_tag_in_git_repository(release.version)
      start_deploys(release)
    end
    release
  end

  def can_release?
    GITHUB.repo(@project.repository_path).permissions[:push]
  rescue Octokit::NotFound, Octokit::Unauthorized
    false
  end

  private

  def push_tag_to_git_repository(version, commit)
    GITHUB.create_release(@project.repository_path, version, target_commitish: commit)
  end

  def ensure_tag_in_git_repository(tag)
    Samson::Retry.with_retries [Octokit::NotFound], 3, wait_time: 1 do
      GITHUB.release_for_tag(@project.repository_path, tag)
    end
  end

  def start_deploys(release)
    deploy_service = DeployService.new(release.author)

    @project.stages.deployed_on_release.each do |stage|
      if Samson::Hooks.fire(:release_deploy_conditions, stage, release).all?
        deploy_service.deploy(stage, reference: release.version)
      end
    end
  end
end
