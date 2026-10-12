/* ==================================================================
   Oracle Select AI Agent: "Sales Analyst" demo
   Ask business questions in plain English; the agent writes and runs
   the SQL inside Autonomous Database.

   Flow:  Profile (LLM)  ->  Tool  ->  Agent  ->  Task  ->  Team  ->  Run
   ================================================================== */


/* ------------------------------------------------------------------
   STEP 0 | As ADMIN: create the demo user and grant privileges
            (skip CREATE USER if the user already exists)
   ------------------------------------------------------------------ */
CREATE USER sales_user IDENTIFIED BY "<YourStrongPassword>";
GRANT CREATE SESSION, CREATE TABLE TO sales_user;
ALTER USER sales_user QUOTA UNLIMITED ON data;

GRANT EXECUTE ON DBMS_CLOUD          TO sales_user;  -- credentials
GRANT EXECUTE ON DBMS_CLOUD_AI       TO sales_user;  -- AI profiles
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO sales_user;  -- agents, tools, tasks, teams


/* ------------------------------------------------------------------
   STEP 1 | Connect as SALES_USER and create sample data
   ------------------------------------------------------------------ */
CREATE TABLE sales_demo (
  sale_id  NUMBER PRIMARY KEY,
  product  VARCHAR2(50),
  region   VARCHAR2(30),
  amount   NUMBER(10,2)
);

INSERT INTO sales_demo VALUES (1, 'Laptop',   'West', 1200);
INSERT INTO sales_demo VALUES (2, 'Keyboard', 'East',  100);
INSERT INTO sales_demo VALUES (3, 'Laptop',   'East',  800);
INSERT INTO sales_demo VALUES (4, 'Mouse',    'West',   50);
INSERT INTO sales_demo VALUES (5, 'Keyboard', 'West',  150);
INSERT INTO sales_demo VALUES (6, 'Monitor',  'East',  300);
COMMIT;


/* ------------------------------------------------------------------
   STEP 2 | Credential: how the database authenticates to OCI
            Replace every placeholder with your own values.
            Never share real OCIDs, keys or fingerprints.
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'OCI_CRED',
    user_ocid       => 'ocid1.user.oc1..xxxx',        -- your user OCID
    tenancy_ocid    => 'ocid1.tenancy.oc1..xxxx',     -- your tenancy OCID
    private_key     => '<private key, one line, no BEGIN/END lines>',
    fingerprint     => '<API key fingerprint>'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 3 | AI profile: the connection to the LLM, plus which tables
            the LLM is allowed to see.
            object_list owner must be the schema that owns SALES_DEMO.
            Optional: if your tenancy is not subscribed to the default
            OCI Generative AI region, add a "region" attribute.
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SALES_PROFILE',
    attributes   => '{
      "provider": "oci",
      "credential_name": "OCI_CRED",
      "oci_compartment_id": "ocid1.compartment.oc1..xxxx",
      "object_list": [{"owner": "SALES_USER", "name": "SALES_DEMO"}]
    }'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 4 | Tool: what the agent can DO (here: natural language to SQL)
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => 'SALES_SQL_TOOL',
    attributes => '{
      "tool_type": "SQL",
      "tool_params": {"profile_name": "SALES_PROFILE"}
    }'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 5 | Agent: who it is (role) and which LLM profile it uses
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SALES_ANALYST',
    attributes => '{
      "profile_name": "SALES_PROFILE",
      "role": "You are a sales analyst. Answer using database results; do not invent figures."
    }'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 6 | Task: the instructions, and which tools it may use
            {query} is replaced by the user's question at run time.
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'SALES_QA_TASK',
    attributes => '{
      "instruction": "Answer the user question: {query}. Use the SQL tool to query the sales data. Show the supporting numbers and state the answer clearly.",
      "tools": ["SALES_SQL_TOOL"]
    }'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 7 | Team: ties the agent to its task
   ------------------------------------------------------------------ */
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'SALES_TEAM',
    attributes => '{
      "agents": [{"name": "SALES_ANALYST", "task": "SALES_QA_TASK"}],
      "process": "sequential"
    }'
  );
END;
/


/* ------------------------------------------------------------------
   STEP 8 | Run it: ask a question in plain English
   ------------------------------------------------------------------ */
SET SERVEROUTPUT ON

DECLARE
  l_answer CLOB;
BEGIN
  l_answer := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'SALES_TEAM',
    user_prompt => 'Rank the products by total sales and identify the top product.'
  );

  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_answer, 32767, 1));
END;
/

-- Expected result, based on the sample data:
--   Laptop 2000 | Monitor 300 | Keyboard 250 | Mouse 50   -> top product: Laptop


/* ------------------------------------------------------------------
   STEP 9 | Or run it with the SELECT AI command
            Once a team is set, only SELECT AI AGENT works in this session.
   ------------------------------------------------------------------ */
EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('SALES_TEAM');

SELECT AI AGENT Which region has the highest total sales?;
