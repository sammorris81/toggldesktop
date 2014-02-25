// Copyright 2014 Toggl Desktop developers.

#ifndef SRC_USER_H_
#define SRC_USER_H_

#include <string>
#include <vector>
#include <set>

#include "./types.h"
#include "./https_client.h"
#include "./workspace.h"
#include "./client.h"
#include "./project.h"
#include "./task.h"
#include "./time_entry.h"
#include "./tag.h"
#include "./related_data.h"
#include "./batch_update_result.h"

#include "Poco/Types.h"

namespace kopsik {

    class User {
    public:
        User(const std::string app_name,
                const std::string app_version) :
            BasicAuthUsername(""),
            BasicAuthPassword(""),
            local_id_(0),
            id_(0),
            api_token_(""),
            default_wid_(0),
            since_(0),
            dirty_(false),
            fullname_(""),
            app_name_(app_name),
            app_version_(app_version),
            email_(""),
            record_timeline_(false) {}
        ~User() {
            ClearWorkspaces();
            ClearClients();
            ClearProjects();
            ClearTasks();
            ClearTags();
            ClearTimeEntries();
        }

        error Sync(HTTPSClient *https_client,
            const bool full_sync,
            const bool with_related_data);
        error Push(HTTPSClient *https_client);
        error Login(HTTPSClient *https_client,
            const std::string &email, const std::string &password);

        std::string String();

        void ClearWorkspaces();
        void ClearClients();
        void ClearProjects();
        void ClearTasks();
        void ClearTags();
        void ClearTimeEntries();

        bool HasPremiumWorkspaces();

        Workspace *GetWorkspaceByID(const Poco::UInt64 id);
        Client *GetClientByID(const Poco::UInt64 id);
        Client *GetClientByGUID(const guid GUID);
        Project *GetProjectByID(const Poco::UInt64 id);
        Project *GetProjectByGUID(const guid GUID);
        Project *GetProjectByName(const std::string name);
        Task *GetTaskByID(const Poco::UInt64 id);
        Tag *GetTagByID(const Poco::UInt64 id);
        Tag *GetTagByGUID(const guid GUID);
        TimeEntry *GetTimeEntryByID(const Poco::UInt64 id);
        TimeEntry *GetTimeEntryByGUID(const guid GUID);

        void CollectPushableTimeEntries(
            std::vector<TimeEntry *> *result);
        void SortTimeEntriesByStart();

        TimeEntry *RunningTimeEntry();
        TimeEntry *Start(
            const std::string description,
            const std::string duration,
            const Poco::UInt64 task_id,
            const Poco::UInt64 project_id);
        TimeEntry *Continue(const std::string GUID);
        TimeEntry *Latest();
        std::vector<TimeEntry *> Stop();
        TimeEntry *SplitAt(const Poco::Int64 at);
        TimeEntry *StopAt(const Poco::Int64 at);

        std::string DateDuration(TimeEntry *te);

        Poco::Int64 LocalID() { return local_id_; }
        void SetLocalID(Poco::Int64 value) { local_id_ = value; }

        Poco::UInt64 ID() { return id_; }
        void SetID(Poco::UInt64 value);

        std::string APIToken() { return api_token_; }
        void SetAPIToken(std::string api_token);

        Poco::UInt64 DefaultWID() { return default_wid_; }
        void SetDefaultWID(Poco::UInt64 value);

        // Unix timestamp of the user data; returned from API
        Poco::UInt64 Since() { return since_; }
        void SetSince(Poco::UInt64 value);

        bool Dirty() { return dirty_; }
        void ClearDirty() { dirty_ = false; }

        std::string Fullname() { return fullname_; }
        void SetFullname(std::string value);

        std::string Email() { return email_; }
        void SetEmail(const std::string value);

        bool RecordTimeline() { return record_timeline_; }
        void SetRecordTimeline(const bool value);

        void ActiveProjects(std::vector<Project *> *list);

        bool StoreStartAndStopTime() { return store_start_and_stop_time_; }
        void SetStoreStartAndStopTime(const bool value);

        // Following 2 fields are not saved into database:
        // They are only used to log user in.
        std::string BasicAuthUsername;
        std::string BasicAuthPassword;

        RelatedData related;

    private:
        error pull(HTTPSClient *https_client,
            const bool full_sync,
            const bool with_related_data);

        std::string dirtyObjectsJSON(std::vector<TimeEntry *> *dirty);
        void processResponseArray(std::vector<BatchUpdateResult> *results,
            std::vector<TimeEntry *> *dirty,
            std::vector<error> *errors);
        error collectErrors(std::vector<error> *errors);

        error requestJSON(std::string method, std::string relative_url,
                std::string json,
                bool authenticate_with_api_token,
                std::string *response_body);
        bool isStatusOK(int status);
        void parseResponseArray(std::string response_body,
            std::vector<BatchUpdateResult> *responses);

        Poco::Int64 local_id_;
        Poco::UInt64 id_;
        std::string api_token_;
        Poco::UInt64 default_wid_;
        // Unix timestamp of the user data; returned from API
        Poco::UInt64 since_;
        bool dirty_;
        std::string fullname_;
        std::string app_name_;
        std::string app_version_;
        std::string email_;
        bool record_timeline_;
        bool store_start_and_stop_time_;
    };

}  // namespace kopsik

#endif  // SRC_USER_H_