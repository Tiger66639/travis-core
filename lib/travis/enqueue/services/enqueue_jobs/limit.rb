module Travis
  module Enqueue
    module Services
      class EnqueueJobs < Travis::Services::Base
        class Limit
          attr_reader :owner, :jobs, :config

          def initialize(owner, jobs)
            @owner = owner
            @jobs  = jobs
            @config = Travis.config.queue.limit
          end

          def queueable
            @queueable ||= filter_by_repository(jobs)
            @queueable[0, max_queueable]
          end

          def filter_by_repository(jobs)
            running_by_repository = running_jobs.each_with_object({}) do |job, acc|
              acc[job.repository_id] ||= 0
              acc[job.repository_id] += 1
            end
            
            queueable_by_repository = {}
            jobs.reject do |job|
              if job.repository.settings.restricts_number_of_builds?
                queueable?(job, queueable_by_repository, running_by_repository)
              end
            end
          end

          def queueable?(job, queueable, running)
            repository = job.repository_id
            queueable[repository] ||= 0

            runnable_count = queueable[repository] + (running[repository] || 0)
            if runnable_count < job.repository.settings.maximum_number_of_builds
              queueable[repository] += 1
              false
            else
              true
            end
          end

          def report
            { total: jobs.size, running: running, max: max_jobs, queueable: queueable.size }
          end

          private

            def running_jobs
              @running_jobs ||= Job.owned_by(owner).running
            end

            def running
              @running ||= Job.owned_by(owner).running.count(:id)
            end

            def max_queueable
              return config.default if owner.login.nil?

              if unlimited?
                999
              else
                queueable = max_jobs - running
                queueable < 0 ? 0 : queueable
              end
            end

            def max_jobs
              config.by_owner[owner.login] || config.default
            end

            def unlimited?
              config.by_owner[owner.login] == -1
            end
        end
      end
    end
  end
end
