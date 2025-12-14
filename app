Firco Continuity V6.13.1.0 Deployment Plan


--------------------------------------------------------------------------------


1.0 Introduction

This document provides a comprehensive, step-by-step deployment plan for Firco Continuity version V6.13.1.0. Its purpose is to guide IT administrators, database administrators, and implementation engineers through the entire process, from initial database setup to final system validation. Adherence to this structured plan is critical for establishing a successful, stable, and secure Firco Continuity environment.

The scope of this deployment plan encompasses the following key phases:

* Database Creation: Preparing and configuring the Oracle or SQL Server database that serves as the system's core data repository.
* Back-End Installation: Installing and configuring the orchestrator-based back-end packages, including the Screening Box, Alert Controller, AHQ Controller, and Infinite Memory.
* Dapr Sidecar Setup: Installing and configuring the Dapr runtime, a necessary dependency for specific features and communication modes.
* Front-End Deployment: Deploying the web-based user interface components for alert review and system administration.
* Security Configuration: Hardening the system through external authentication, HTTPS communication, and password encryption.
* Post-Installation Validation: Performing initial system checks to confirm a successful deployment.

To begin, we will address the essential system-level prerequisites that must be in place before the installation process commences.

2.0 Pre-Deployment System Requirements and Considerations

Addressing system-level prerequisites before initiating the installation is a strategic step that prevents common configuration errors, ensures component interoperability, and establishes a stable foundation for the entire deployment. These preliminary checks are essential for a smooth and predictable installation process.

Port Conflict Management

It is critical to assign distinct network ports for each component instance deployed on the same machine to prevent resource conflicts. While Java-based back-ends will typically display an error message if a port is already in use, Core Engine back-ends do not display a warning for port reuse. This requires extra caution during configuration to avoid silent failures or unpredictable behavior. A systematic approach to port allocation across all components is mandatory for any multi-instance deployment.

Server Clock Synchronization

To maintain data integrity and consistent event logging across the distributed components of Firco Continuity, it is highly recommended to synchronize the system clocks on all servers involved in the deployment. Synchronized clocks prevent inconsistent timestamps between events, which is crucial for auditing, troubleshooting, and accurate reporting.

With these foundational considerations addressed, the first active deployment phase is the preparation of the database.

3.0 Phase 1: Database Preparation and Configuration

The Firco Continuity database is the central repository for all system data, including alerts, user decisions, and configuration settings. Its correct creation and configuration are foundational to the functionality, performance, and stability of the entire system. This section outlines the precise requirements and procedures that must be performed by a qualified database administrator.

3.1 Database Requirements

Before executing any creation scripts, ensure the target database environment meets the specific requirements for your chosen vendor.

Oracle Requirements

Requirement	Description
Account	An Oracle database user with an associated password must be created for schema creation and runtime operations.
System/Object Privileges	The user account must be granted CONNECT and RESOURCE privileges for installation and runtime access.
Tables	The quartz-schema-oracle.sql script must be run to add Quartz tables. When migrating to V6.12.x or higher from a version older than V6.12.0.0, Spring Batch tables must be dropped and recreated using batch-schema-drop-oracle.sql and batch-schema-oracle.sql.
Tablespaces	At least two tablespaces should be created: one for data and one for indexes to improve data organization.
Software Parameters	The Oracle instance must be configured with NLS_LENGTH_SEMANTICS set to BYTE and NLS_CHARACTERSET set to AL32UTF8.
Log Folder	A Log folder must be created in the same location as the SQL script being executed.

SQL Server Requirements

Requirement	Description
Account	A SQL Server database user with an associated password must be created for schema creation and runtime operations.
Collation	The database collation must be set to SQL_Latin1_General_CP1_CI_AS.
Read Committed Snapshot Isolation (RCSI)	The RCSI option must be enabled to handle concurrent read and write operations effectively.
Tables	The quartz-schema-sqlServer.sql script must be run to add Quartz tables. When migrating to V6.12.x or higher from a version older than V6.12.0.0, Spring Batch tables must be dropped and recreated using batch-schema-drop-sqlserver.sql and batch-schema-sqlServer.sql.

3.2 Database Creation and Licensing

The following steps outline the creation of the core and optional databases.

1. Create the Core Continuity Database:
  * Connect to the target database server.
  * Create a new, empty database.
  * Ensure all vendor-specific requirements from section 3.1 are met.
  * Using the appropriate vendor tool (SQL*Plus for Oracle, sqlcmd for SQL Server), execute the Continuity_xxxx_Creation_yyy.sql script.¹ Using other tools like SQL Developer may cause issues.
  * For Oracle, specify the data and index tablespaces as command-line attributes or when prompted.
2. Register the Continuity License:
  * Once the database is created, run the provided license script against the new database.
  * Commit the transaction to finalize the registration.
3. Create the Advanced Reporting Database (If Applicable):
  * If the Advanced Reporting module is part of the implementation, a separate, dedicated database must be created.
  * Follow the same procedure as the core database creation, but use the AdvancedReporting_xxxx_Creation_yyy.sql script.²


--------------------------------------------------------------------------------


¹ xxxx is the LexisNexis® Firco™ Continuity database schema version on 4 digits, yyy is the database vendor. ² xxxx is the Advanced Reporting database schema version on 4 digits, yyy is the database vendor.

3.3 Schema and Table Management

Certain components require additional tables to function. These are created by running the batch-schema-<db_provider>.sql script, which is located in the sql folder of the respective component package.

Component Requiring Additional Tables	Database for Script Execution
Advanced Reporting	LexisNexis® Firco™ Continuity database
Archiving	LexisNexis® Firco™ Continuity database
Migration Tool	Source and Target LexisNexis® Firco™ Continuity databases
Onboarding	LexisNexis® Firco™ Continuity database

For database schema migrations (upgrades), it is mandatory to stop all application access to the database before proceeding. The migration is performed by running the appropriate Continuity_xxxx_To_yyyy_zzz.sql or AdvancedReporting_xxxx_To_yyyy_zzz.sql script using vendor-specific command-line tools.

Once the database foundation is correctly established and licensed, the next step is to install the back-end processing engines.

4.0 Phase 2: Orchestrator-Based Back-End Installation

The orchestrator-based packages form the core back-end processing layer of Firco Continuity. These packages—Screening Box, Alert Controller, AHQ Controller, and Infinite Memory—are responsible for message processing, screening, alert generation, and data archiving. This phase covers the installation and configuration of these essential services.

4.1 Screening Box Installation and Configuration

The Screening Box package contains the necessary components to screen messages against sanction lists and produce alerts for review.

Installation Steps

1. Core Product Installation:
  * Extract the main Screening Box package into a dedicated installation directory.
  * Extract the required core binary, configuration, and script sub-packages in the following order: [00-SB], then [01-FilterV5]. It is critical that you accept all file overwrites during extraction.
  * Copy the back-end license file (fbe.cf) into the conf\ScreeningBox folder.
  * Copy the Filter Engine license file (fof.cf) into the bin\ScreeningBox\FilterEngine folder.
  * Copy the Filter Engine configuration files (fkof.res, .t/.kz files) into the conf\ScreeningBox\FilterEngine folder.
2. Stripping Detector Installation:
  * Extract the [02-Stripping] sub-packages.
  * Edit ScreeningBox\.env_stripping to provide the required database connection details.
3. ERF Requester Installation:
  * Extract the [03-ERF] sub-packages.
  * Extract the separately downloaded Entity Resolution Filter package and copy its contents into the appropriate bin, conf, and license directories within the Screening Box installation.
  * Note that this feature requires the 'Alert Review and Decision Workflow API Injector' to be installed on the Alert Controller.
4. Automated Hit Qualifier (AHQ) Installation:
  * For Production and Simulation modes, extract the [04-AHQ] sub-packages.
  * For Learning mode (optional), extract the [04-AHQ] learning-specific sub-packages.
5. Prediction Integrator Installation:
  * Extract the [05-PI] sub-packages.
  * Note that this feature also requires the 'Alert Review and Decision Workflow API Injector' on the Alert Controller.
6. Context Recorder Module Installation:
  * Extract the [06-ContextRecorder] sub-packages. This module is mandatory for the Infinite Memory feature.
7. Filter V6 Installation:
  * Extract the [07-FilterV6] sub-packages.

Main Parameter Configuration

The primary configuration for the Screening Box is managed in the ScreeningBox\.env file. A critical parameter is SCREENING_BOX_TRANSPORT_MODE, which defines the communication method.

* Possible Values:
  * DIR: Directory-based file transfer (default).
  * MQ: IBM MQ.
  * HTTP: HTTP-based communication.
  * PUBSUB: Publish-Subscribe model (requires Dapr).

Service Management

* To Start Screening Box: Run the Start_ScreeningBox script in the ScreeningBox folder.
* To Stop Screening Box: Run the Stop_ScreeningBox script in the ScreeningBox folder.

Configuring Multiple Screening Box Instances

To run multiple instances on the same server, you must update the configuration to avoid conflicts:

1. Update Environment Variables: Modify the .env files of the new instance to assign unique ports for all components (e.g., SERVER_PORT, SCREENING_BOX_DAPR_PORT).
2. Update Pub/Sub Configuration: If using PUBSUB mode, edit screening_inbound.yml to define a unique subscription topic name for the new instance.
3. Update Directory Mode Paths: If using DIR mode, edit dir.yml to specify unique input/output folder paths.
4. Update IBM MQ Queues: If using MQ mode, edit mq.yml to specify unique input queues.

Essential Environment Variables

The following table details critical environment variables for the Screening Box.

Variable	File	Description
SCREENING_BOX_TRANSPORT_MODE	.env	Sets the primary communication mode (DIR, MQ, HTTP, PUBSUB).
SERVER_PORT	.env	Defines the HTTP server port for functional endpoints (e.g., receiving screening requests).
MANAGEMENT_SERVER_PORT	.env	Defines the HTTP server port for administrative endpoints.
AHQ_ENABLED	.env_ahq	When true, enables the Automated Hit Qualifier Requester.
ERF_REQUESTER_HOST / PORT	.env_erf	Specifies the connection details for the external Entity Resolution Filter engine. Enabled by setting ERF_ENABLED=true in the main .env file.
REQUESTER_ENABLED	.env_requester	When true, enables the Filter Requester for communication with the Filter Engine.
STRIPPING_ENABLED	.env_stripping	When true, enables the Stripping Detector Requester.
DATABASE_VENDOR	.env_stripping	Specifies the database provider (Oracle or Sqlserver) for the Stripping Detector.

4.2 Alert Controller Installation and Configuration

The Alert Controller package processes alerted messages from the Screening Box, enriches them, and inserts them into the database for user review in the front-end application.

Installation Steps

1. Core Product Installation:
  * Extract the main Alert Controller package into a dedicated directory.
  * Extract the [00-AC] sub-packages, accepting file overwrites.
  * Copy the fbe.cf license file into the conf\AlertController folder.
  * Edit AlertController\.env to configure database connection parameters (DATABASE_VENDOR, DATABASE_HOST, etc.).
2. Alert Review and Decision Workflow Installation:
  * Extract the [01-AlertReview] sub-packages. This module provides the front-end application and its API.
  * After installation, edit AlertController\.env_AlertReviewApi to set the AUTH_USER and AUTH_API_KEY credentials. These are used by the Alert Controller to call the Apply Decision API.
3. Alert Review and Decision Workflow API Injector Installation:
  * Extract the [02-Injector-AlertReviewAPI] configuration sub-package. This component replaces the legacy DB Client for database injection and is mandatory for ERF, AHQ, and Prediction Integrator.
4. Automated Hit Qualifier Installation:
  * Extract the [03-AHQ] configuration sub-package.
5. Decision Reapplication Installation:
  * Extract the [04-DecisionReapplication] sub-packages.
6. Pairing Manager Installation:
  * Extract the [05-Pairing] sub-packages.
7. Workflow Accelerator Installation:
  * Extract the [06-WorkflowAccelerator] sub-packages.
8. Installation of Plugins:
  * Install plugins for Infinite Memory and the Case Manager API by extracting the respective sub-packages: [07-PushEvent-AlertReviewAPI], [08-ContextRecorder-AlertReviewAPI], [09-InfiniteMemory], and [10-CMAPI].

Main Parameter Configuration

The main transport mode for the Alert Controller is set in the AlertController\.env file via the ALERT_CONTROLLER_TRANSPORT_MODE parameter.

* Possible Values: DIR, HTTP, PUBSUB. MQ is also supported for specific configurations.

Service Management

* To Start Alert Controller: Run the Start_AlertController script in the AlertController folder.
* To Stop Alert Controller: Run the Stop_AlertController script in the AlertController folder.

Essential Environment Variables

The following table details critical environment variables for the Alert Controller.

Variable	File	Description
ALERT_CONTROLLER_TRANSPORT_MODE	.env	Sets the primary communication mode (DIR, HTTP, PUBSUB).
DATABASE_VENDOR, HOST, PORT, USER, PASSWORD_JAVA, PASSWORD_COREENGINE	.env	Defines the connection parameters and credentials for the main Continuity database.
ALERT_REVIEW_API_ENABLED	.env_AlertReviewApi	When true, enables the Alert Review and Decision Workflow API.
AUTH_USER / AUTH_API_KEY	.env_AlertReviewApi	Sets the credentials used by the Alert Controller to apply decisions via the API.
DBCLIENT_ENABLED	.env_DBClient	When true, enables the legacy DB Client for database injection. This should be disabled if using the API Injector.
AHQ_ENABLED_ALERT_REVIEW_API	.env_Z_AlertReviewApi_Ahq	When true, enables API functionalities required for Automated Hit Qualifier.

4.3 Automated Hit Qualifier (AHQ) Controller Installation

The AHQ Controller package provides centralized management for the Automated Hit Qualifier feature, including memory management and context administration.

Installation Steps

1. Core Product Installation:
  * Extract the AHQ Controller package into a dedicated directory.
  * Extract the [00-AHQC] core sub-packages.
  * Copy the fbe.cf license file to the conf\AHQController folder.
2. AHQ Memory Manager Installation:
  * Extract the [01-AHQMM] sub-packages.
3. AHQ Context Management API Installation (Optional):
  * Extract the [02-AHQCMAPI] sub-packages. This plugin allows context management from the Alert Review UI.
  * Edit AHQController\.env_AHQAPI to configure the database connection details for this API.
  * Dependency: If you install this component, you must also install the Automated Hit Qualifier plugin for Alert Controller.

Main Parameter Configuration

The primary transport mode is set in AHQController\.env via the AHQ_CONTROLLER_TRANSPORT_MODE parameter.

* Possible Values: DIR, MQ, HTTP, PUBSUB.

Service Management

* To Start AHQ Controller: Run the Start_AHQController script.
* To Stop AHQ Controller: Run the Stop_AHQController script.

4.4 Infinite Memory Installation

The Infinite Memory package is used for archiving and managing large volumes of historical screening data.

Installation Steps

1. Database Preparation:
  * On a dedicated database for the Iceberg catalog, run the IMIcebergJDBCCatalog-<version>_Creation_<db_vendor>.sql script.
  * On a dedicated database for the Datawarehouse projection, run the IMDataWarehouse_1000_Creation_<db_vendor>.sql script.
2. Core Product Installation:
  * Extract the Infinite Memory package into a dedicated directory.
  * Extract the [00-IM] core sub-packages.
  * Copy the fbe.cf license to the conf\IMController and conf\IMDataJobs folders.
  * Edit IMDataJObs\.env to configure the JDBC connection details for the Catalog and Warehouse databases.
3. Object Storage / NFS Configuration (Optional):
  * If the Iceberg warehouse is located on an object storage service (e.g., S3) or a network file system (NFS), additional configuration is required. Update flink\config.yaml with the appropriate file system properties (e.g., fs.s3a.* parameters) and update the transport mode files (e.g., dir.yml) to define the object storage endpoint.
4. Create Iceberg Tables:
  * Run the start_im_data_maintenance_catalog_initializer script to create the necessary tables in the Iceberg catalog.
5. Start Projector Jobs:
  * Configure the datawarehouse properties in conf\IMDataJobs\im.common.properties.
  * Run the start_projector_realtime or start_projector_batch script to begin loading data from the Iceberg catalog into the relational datawarehouse.
6. Load V5 and V6 Archives:
  * Configure the archive loader properties in im.archive-loader-v5.properties or im.archive-loader-v6.properties.
  * Run the start_archiveV5_ingestor or start_archiveV6_ingestor script and copy extracted archives into the designated input directory.
7. Install Additional Modules:
  * Install the Data Maintenance, Data API, and Object API modules by extracting their respective sub-packages ([01-IM], [02-IM], [03-IM]).

With the back-end services installed, the next step is to install and configure the Dapr dependency that enables key features.

5.0 Phase 3: Dapr Sidecar Installation and Configuration

Dapr is a critical sidecar component within the Firco Continuity ecosystem, enabling advanced features and communication patterns. It is required for functionalities like Automated Hit Qualifier and for inter-component communication when operating in pub/sub mode. Dapr provides a standardized interface to various infrastructure components, with official support in Continuity for:

* State store: Redis, SQL Server, Oracle
* Pub/sub: Kafka
* Secret store: HashiCorp Vault

5.1 Installation

The Dapr installation is a straightforward three-step process:

1. Unzip the provided Dapr installation package.
2. Run the installation script included in the package.
3. Add the directory containing the Dapr command-line interface (CLI) to your system's PATH environment variable to ensure the command is accessible from any location.

5.2 Configuration

Dapr is configured via YAML files located in a dapr directory within each Firco Continuity component's folder (e.g., conf\ScreeningBox\Orchestrator\dapr\). These files must be updated to match the specific details of your target environment.

For example, to connect to your Kafka and Redis instances, you would update the following files:

* Kafka (kafka-config.yml): Update the brokers value to point to your Kafka broker's host and port.
* Redis (statestore.yaml): Update the redisHost value to point to your Redis server's host and port.

After configuring the Dapr sidecar, the next phase is to deploy the user-facing front-end components.

6.0 Phase 4: Front-End Deployment and Configuration

The front-end components provide the user interface for alert review, system administration, and other user-driven activities. This section covers the deployment of the 'Alert Review and Decision Workflow' application and its associated API, along with essential configurations for performance, security, and functionality.

6.1 Deployment and Execution

Load Balancing

For production environments with multiple instances, it is strongly recommended to use a load balancer to distribute traffic across the 'Alert Review and Decision Workflow' application and its API. This architecture improves system resiliency and scalability. The application is stateless, so no session persistence or cookie management is required at the load balancer level.

Health Check Endpoints

The load balancer should be configured to monitor the health of each component instance using the following health check endpoints:

Module	Component	Health Check Type	Endpoint
Alert Review and Decision Workflow	Jetty Server	Default	http://localhost:5902/actuator/health
Alert Review and Decision Workflow	Jetty Server	Global Health	http://localhost:5902/actuator/global-health
Alert Review and Decision Workflow API	Tomcat Server	Default	http://localhost:5900/continuity-services/actuator/health

Service Management

* To Start Front-End Components:
  1. Run the Start_ContinuityAlertReviewApi script.
  2. Run the Start_ContinuityAlertReview script.
* To Stop Front-End Components:
  1. Run the Stop_ContinuityAlertReviewApi script.
  2. Run the Stop_ContinuityAlertReview script.

6.2 Application Configuration

Primary configuration for the front-end is managed in the ContinuityAlertReviewApi.properties and ContinuityAlertReview.yml files, located in their respective conf folders.

File Upload Restrictions

To enhance security, you can restrict the types of files that users can upload as attachments. This is configured in ContinuityAlertReviewApi.properties:

* global-config.file.extension-restriction-enabled: Set to true to enable the restriction.
* global-config.file.permitted-extensions: Provide a comma-separated list of allowed file extensions (e.g., .txt, .pdf, .doc).

Apply Decision API

The Apply Decision API requires credentials to be configured for use by back-end components like the Alert Controller.

Parameter	Description
auth.user	The authentication user for the API. A value is required.
auth.apikey	The authentication key for the API. A value is required.

Manual Screening

The Manual Screening feature allows users to submit screening queries directly from the UI. The following mandatory parameters must be configured in ContinuityAlertReviewApi.properties.

Parameter	Description
manual.screening.enabled	Set to true to enable the feature in the UI.
manual.screening.backend	Defines the back-end component to connect to. Default is OREN.
manual.screening.target.url	The URL of the Screening Box back-end that will process manual screening requests.
manual.screening.target.method	The HTTP method to use. Default is POST.
manual.screening.retry.times	The maximum number of retry attempts if a connection fails.
manual.screening.retry.delay	The delay in milliseconds between retry attempts.

With the core application now running, the next crucial step is to configure authentication and security settings to protect the system.

7.0 Phase 5: Authentication and Security Hardening

Properly configuring authentication and security settings is a critical step in deploying a production-ready Firco Continuity system. This phase provides guidance on integrating with external authentication providers like LDAP and SAML, securing communications with HTTPS, and encrypting sensitive data such as database passwords within configuration files.

7.1 External Authentication

LDAP Authentication

To configure authentication against an LDAP directory, set the following parameters in ContinuityAlertReviewApi.properties:

Parameter	Description
ldap.url	The URL of the LDAP server.
ldap.connectionName	The Distinguished Name (DN) of the manager user for authenticating to the server.
ldap.connectionPassword	The password for the manager DN.
ldap.userBase	The search base for locating user accounts.
ldap.userSearch	The LDAP filter used to search for a specific user (e.g., (uid={0})).
ldap.roleBase	The search base for group membership searches.
ldap.roleSearch	The LDAP filter used to find a user's groups (e.g., (uniqueMember={0})).

SAML Authentication

Firco Continuity supports SP-initiated Single Sign-On (SSO) using SAML. The following minimal set of parameters must be configured in ContinuityAlertReviewApi.properties:

* saml.service-provider.entity-id: The unique identifier for the Continuity application.
* saml.service-provider.alias: An alias used to construct the SAML endpoint URL.
* saml.service-provider.providers.metadata: The URL or file path to the Identity Provider's metadata.
* saml.service-provider.url: The absolute base URL of the Continuity application.
* saml.service-provider.sign-requests: Set to true to sign authentication requests.
* saml.service-provider.signing.private-key.location and password: Path and password for the private key used for signing.
* saml.service-provider.signing.certificate.location: Path to the corresponding certificate.
* saml.service-provider.decryption.private-key.location and password: Path and password for the private key used for decrypting SAML responses.
* saml.service-provider.decryption.certificate.location: Path to the corresponding decryption certificate.

SAML User Provisioning: This feature automates user creation and authorization management based on information received from the identity provider, centralizing user lifecycle management. Note: The SAML User Provisioning feature (saml.user-provisioning.enable=true) requires a separate, specific license and must not be enabled without it.

7.2 Securing Communications (HTTPS)

To encrypt traffic between users and the front-end, HTTPS must be configured.

1. Configure the Alert Review API (Tomcat):
  * In ContinuityAlertReviewApi.properties, set server.ssl.enabled=true.
  * Provide the path to your keystore (server.ssl.key-store), the keystore password (server.ssl.key-store-password), and the key alias (server.ssl.key-alias).
2. Configure the Alert Review Application (Jetty):
  * In ContinuityAlertReview.yml, set the API URI to use HTTPS: alert-review.down-stream.alert-review-api.uri: https://....
  * Under the server.ssl and management.server.ssl sections, set enabled: true.
  * Provide the path to your keystore (key-store), keystore password (key-store-password), and key alias (key-alias).

7.3 Password Encryption

To avoid storing sensitive passwords in plain text, Firco Continuity provides two encryption methods.

* Core Engine Components: For Core Engine configuration files, use the FKRUN -password <YourPassword> command located in the bin32 folder. The output must be pasted into the configuration file using the syntax 'password("...")'.
* Java Back-Ends: For Java-based components, use the dedicated Encryption Tool located in the tools/EncryptionTool folder of the component package.
  * Simple Encryption: Run encrypt --input=<YourPassword>.
  * Strong Encryption: Run encrypt --input=<YourPassword> --password=<EncryptionKey> to use a master password for encryption. The master password must then be provided at runtime when starting the component.

With security measures in place, the deployment is ready for final validation.

8.0 Phase 6: Post-Deployment Validation

This final phase validates that the installation and configuration of the Firco Continuity system have been completed successfully. Performing this simple check confirms that the database, back-end, and front-end components are communicating correctly.

Follow these steps to test the base installation:

1. Open a web browser and navigate to the application URL: http://<serverHost>:<serverPort>/<contextPath>/.
2. At the login page, enter the default administrator credentials:
  * Login: #admin1
  * Password: admin1
3. Upon first login, the system will require you to change the password immediately. Follow the on-screen prompts to set a new, secure password.
4. Successful login to the main application interface confirms that the base installation of Firco Continuity is complete and operational.

After confirming a successful deployment, it is useful to be aware of common troubleshooting steps for resolving potential issues.

9.0 Troubleshooting Guide

This section provides solutions for common issues that may be encountered during or after the deployment of Firco Continuity.

Issue	Resolution
Unable to access the application	1. Verify that you are using the correct login and password.<br>2. Confirm that all required front-end and back-end services have been started and are running without errors.
Reports are generated as empty Word documents	This typically occurs when the application server is running on a non-GUI operating system like Linux. To resolve this, start the application server with the -Djava.awt.headless=true Java Virtual Machine (VM) option.
Dapr sidecar does not stop properly	If a Dapr process persists after a component is stopped, it must be terminated manually:<br>1. Run dapr list to find the persistent Dapr sidecar and its process ID (PID).<br>2. Use ps -eaf | grep <PID> (on Linux) or an equivalent command to confirm the process.<br>3. Terminate the process using kill <PID>. If necessary, use kill -9 <PID> to force termination.
