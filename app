Based on the provided user manual for LexisNexis® Firco™ Continuity Back-Ends, here is the full flow of how the components interact to process a transaction (such as a Visa request), followed by an explanation of the key components and their purposes.

### **High-Level Architecture**

The solution architecture consists of two main packages built on the **Orchestrator** component:
1.  **Screening Box:** Handles the input, parsing, and screening (detection) of messages.
2.  **Alert Controller:** Handles the management of alerts, database insertion, notifications, and workflow decisions (remediation),.

---

### **Full Flow: Processing a Visa Transaction**

In this scenario, we assume a Visa transaction arrives via a standard protocol (such as HTTP or MQ) in a format like JSON or XML.

#### **Phase 1: Input and Normalization (Screening Box)**
1.  **Consumption:** The Visa transaction arrives at an **Input Endpoint** (e.g., HTTP or IBM MQ) defined in the Screening Box configuration.
2.  **Parsing & Mapping:** The **Universal Mapper** (embedded in the Orchestrator) picks up the message. It uses a defined **Consumer** configuration to parse the input (e.g., using a JSON or XML parser) and map the Visa fields into the internal **FircoContract** or **Firco Unique Format (FUF)**,.
3.  **Metadata Extraction:** The system extracts key metadata (Amount, Currency, Reference) used for routing and screening. If metadata is missing, default values (e.g., Unit: WMQ, Priority: 0) are applied.

#### **Phase 2: Screening and Detection (Screening Box)**
4.  **Dispatching:** The **Dispatcher** (a set of FCL rules) determines the screening strategy. It checks if the message is globally eligible for screening,.
5.  **Filtering:** The message is sent to the **Screening Box Requester** (Universal Requester), which interfaces with the **Filter Engine**. The engine screens the message against sanctions lists.
6.  **Secondary Analysis (Optional Engines):** If the Filter Engine finds "Hits" (potential matches), the Dispatcher may route the message to advanced modules to reduce false positives:
    *   **Stripping Detector:** Checks if the message was altered to bypass filters.
    *   **Entity Resolution Filter (ERF):** Sends the hits to an external ERF tool for secondary scoring to reduce blocking hits.
    *   **Automated Hit Qualifier (AHQ):** Checks historical data to see if these specific hits have been qualified as "False" in the past.
    *   **Prediction Integrator (PI):** Sends the message to a prediction engine API to calculate a probability score for the hit.

#### **Phase 3: Status Resolution (Screening Box)**
7.  **Status Calculation:** The `StatusMsgResolution` function calculates the final status of the message based on the results from the engines. For example, if AHQ qualifies all hits as "False," the status becomes `PASSED_AUTO`. If hits remain, it is `HITS` (Blocking).
8.  **Routing:**
    *   **No Hits / Passed:** If the message is clean, the Screening Box can be configured to produce a response immediately back to the banking application.
    *   **Alerted:** If the message has blocking hits, it is routed to the **Alert Controller** via an internal endpoint (using the FircoContract format).

#### **Phase 4: Alert Management (Alert Controller)**
9.  **Ingestion:** The **Alert Controller** consumes the message from the Screening Box.
10. **Database Insertion:** The Alert Controller (via **DB Client** or **Alert Review and Decision Workflow API**) inserts the alerted message and its hits into the **LexisNexis® Firco™ Continuity Database**,.
11. **Storage (Infinite Memory):** If configured, the message data and events are also propagated to **Infinite Memory** (object storage and data warehouse) for archiving and reporting.

#### **Phase 5: Decision and Notification (Alert Controller)**
12. **Review:** A Compliance Officer reviews the alert in the *Alert Review and Decision Workflow* interface.
    *   Alternatively, **Decision Reapplication** may automatically apply a decision if an identical transaction was previously reviewed,.
    *   **Workflow Accelerator** may automatically route or assign the alert based on specific rules (e.g., high priority for high amounts).
13. **Output Generation:** Once a final decision is made (e.g., "Good to Pay"), the Alert Controller generates a notification.
14. **Production:** The **Universal Mapper** formats the output response (e.g., creating a JSON response or a WMQOUT buffer).
15. **Transmission:** The response is sent back to the source system (Visa payment application) via the configured **Output Endpoint**.

---

### **Component Explanation**

| Component | Purpose |
| :--- | :--- |
| **Orchestrator** | The core Java component that manages message flows. It replaces the legacy Core Engine. It defines **Consumers** (inputs), **Dispatchers** (logic/routing), and **Producers** (outputs),. |
| **Universal Mapper** | A layer within Orchestrator responsible for transforming data. It maps input formats (like ISO 20022, JSON, SWIFT) into internal formats (FUF) for screening and maps results back to the external system format for notifications. |
| **Screening Box** | An Orchestrator-based package dedicated to the **detection** phase. It handles parsing, connects to the Filter Engine, and executes advanced reduction logic (AHQ, ERF). |
| **Alert Controller** | An Orchestrator-based package dedicated to **remediation**. It manages the lifecycle of an alert after detection, including database insertion, workflow management, and final status notification. |
| **Universal Requester** | A component that allows Orchestrator to interface with external engines (like the Filter, ERF, or Prediction Integrator) via HTTP connections. |
| **Automated Hit Qualifier (AHQ)** | A module that automatically resolves recurring false positive hits based on historical operator qualifications. It creates "contexts" (signatures) for hits to recognize them in future transactions. |
| **Decision Reapplication** | A component that recognizes the "footprint" (checksum) of a whole transaction. If a similar transaction comes in (e.g., a recurring monthly salary), it reapplies the previous operator's decision,. |
| **Infinite Memory** | A storage solution that manages large volumes of data. It offloads data from the operational database to object storage (like S3) and provides a data warehouse for reporting and history retrieval,. |
| **DB Client** | A legacy component (being replaced by APIs in newer versions) used to manage communication with the SQL database, insert transactions, and generate reports,. |
