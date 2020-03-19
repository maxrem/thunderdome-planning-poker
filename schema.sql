--
-- Tables
--
CREATE TABLE IF NOT EXISTS battles (
    id UUID NOT NULL PRIMARY KEY,
    leader_id UUID,
    name VARCHAR(256),
    voting_locked BOOL DEFAULT true,
    active_plan_id UUID
);

CREATE TABLE IF NOT EXISTS warriors (
    id UUID NOT NULL PRIMARY KEY,
    name VARCHAR(64)
);

CREATE TABLE IF NOT EXISTS plans (
    id UUID NOT NULL PRIMARY KEY,
    name VARCHAR(256),
    points VARCHAR(3) DEFAULT '',
    active BOOL DEFAULT false,
    battle_id UUID references battles(id) NOT NULL,
    votes JSONB DEFAULT '[]'::JSONB
);

CREATE TABLE IF NOT EXISTS battles_warriors (
    battle_id UUID references battles NOT NULL,
    warrior_id UUID REFERENCES warriors NOT NULL,
    active BOOL DEFAULT false,
    PRIMARY KEY (battle_id, warrior_id)
);

--
-- Table Alterations
--
ALTER TABLE battles ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT NOW();
ALTER TABLE warriors ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT NOW();
ALTER TABLE plans ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT NOW();
ALTER TABLE warriors ADD COLUMN IF NOT EXISTS last_active TIMESTAMP DEFAULT NOW();
ALTER TABLE plans ADD COLUMN IF NOT EXISTS updated_date TIMESTAMP DEFAULT NOW();
ALTER TABLE battles ADD COLUMN IF NOT EXISTS updated_date TIMESTAMP DEFAULT NOW();
ALTER TABLE plans ADD COLUMN IF NOT EXISTS skipped BOOL DEFAULT false;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS votestart_time TIMESTAMP DEFAULT NOW();
ALTER TABLE plans ADD COLUMN IF NOT EXISTS voteend_time TIMESTAMP DEFAULT NOW();
ALTER TABLE battles ADD COLUMN IF NOT EXISTS point_values_allowed JSONB DEFAULT '["1/2", "1", "2", "3", "5", "8", "13", "?"]'::JSONB;
ALTER TABLE warriors ADD COLUMN IF NOT EXISTS email VARCHAR(320) UNIQUE;
ALTER TABLE warriors ADD COLUMN IF NOT EXISTS password TEXT;
ALTER TABLE warriors ADD COLUMN IF NOT EXISTS rank VARCHAR(128) DEFAULT 'PRIVATE';

--
-- Stored Procedures
--

-- Reset All Warriors to Inactive, used by server restart --
CREATE OR REPLACE PROCEDURE deactivate_all_warriors()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE battles_warriors SET active = false WHERE active = true;
END;
$$;

-- Create a Battle Plan --
CREATE OR REPLACE PROCEDURE create_plan(battleId UUID, planId UUID, planName VARCHAR(256))
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO plans (id, battle_id, name) VALUES (planId, battleId, planName);
END;
$$;

-- Activate a Battles Plan, and de-activate any current active plan
CREATE OR REPLACE PROCEDURE activate_plan_voting(battleId UUID, planId UUID)
LANGUAGE plpgsql AS $$
BEGIN
    -- set current active to false
    UPDATE plans SET updated_date = NOW(), active = false WHERE battle_id = battle_id;
    -- set PlanID active to true
    UPDATE plans SET updated_date = NOW(), active = true, skipped = false, points = '', votestart_time = NOW(), votes = '[]'::jsonb WHERE id = planId;
    -- set battle VotingLocked and ActivePlanID
    UPDATE battles SET updated_date = NOW(), voting_locked = false, active_plan_id = planId WHERE id = battleId;
    COMMIT;
END;
$$;

-- Skip a Battles Plan Voting --
CREATE OR REPLACE PROCEDURE skip_plan_voting(battleId UUID, planId UUID)
LANGUAGE plpgsql AS $$
BEGIN
    -- set current active to false
    UPDATE plans SET updated_date = NOW(), active = false, skipped = true, voteend_time = NOW() WHERE battle_id = battleId;
    -- set battle VotingLocked and activePlanId to null
    UPDATE battles SET updated_date = NOW(), voting_locked = true, active_plan_id = null WHERE id = battleId;
    COMMIT;
END;
$$;

-- End a Battles Plan Voting --
CREATE OR REPLACE PROCEDURE end_plan_voting(battleId UUID, planId UUID)
LANGUAGE plpgsql AS $$
BEGIN
    -- set current active to false
    UPDATE plans SET updated_date = NOW(), active = false, voteend_time = NOW() WHERE battle_id = battleId;
    -- set battle VotingLocked
    UPDATE battles SET updated_date = NOW(), voting_locked = true WHERE id = battleId;
    COMMIT;
END;
$$;

-- Finalize a plan --
CREATE OR REPLACE PROCEDURE finalize_plan(battleId UUID, planId UUID, planPoints VARCHAR(3))
LANGUAGE plpgsql AS $$
BEGIN
    -- set plan points and deactivate
    UPDATE plans SET updated_date = NOW(), active = false, points = planPoints WHERE id = planId;
    -- reset battle active_plan_id
    UPDATE battles SET updated_date = NOW(), active_plan_id = null WHERE id = battleId;
    COMMIT;
END;
$$;

-- Revise Plan Name --
CREATE OR REPLACE PROCEDURE revise_plan_name(planId UUID, planName VARCHAR(256))
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE plans SET updated_date = NOW(), name = planName WHERE id = planId;
END;
$$;

-- Delete a plan --
CREATE OR REPLACE PROCEDURE delete_plan(battleId UUID, planId UUID)
LANGUAGE plpgsql AS $$
DECLARE active_plan_id UUID;
BEGIN
    active_plan_id := (SELECT b.active_plan_id FROM battles b WHERE b.id = battleId);
    DELETE FROM plans WHERE id = planId;
    
    IF active_plan_id = planId THEN
        UPDATE battles SET updated_date = NOW(), voting_locked = true, active_plan_id = null WHERE id = battleId;
    END IF;
    
    COMMIT;
END;
$$;

-- Set Battle Leader --
CREATE OR REPLACE PROCEDURE set_battle_leader(battleId UUID, leaderId UUID)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE battles SET updated_date = NOW(), leader_id = leaderId WHERE id = battleId;
END;
$$;

-- Delete Battle --
CREATE OR REPLACE PROCEDURE delete_battle(battleId UUID)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM plans WHERE battle_id = battleId;
    DELETE FROM battles_warriors WHERE battle_id = battleId;
    DELETE FROM battles WHERE id = battleId;

    COMMIT;
END;
$$;