/*
  # Update handle verification functions

  1. Changes
    - Drop existing trigger first
    - Drop existing functions
    - Create new handle validation function
    - Create new handle verification function
    - Create new user trigger function
    - Update mock data with handles

  2. Security
    - Validate handle format
    - Ensure unique handles
    - Safe handle generation
*/

-- Drop existing trigger first
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop existing functions
DROP FUNCTION IF EXISTS verify_user_handle(uuid, text);
DROP FUNCTION IF EXISTS validate_handle(text);
DROP FUNCTION IF EXISTS handle_new_user();

-- Create handle validation function
CREATE OR REPLACE FUNCTION validate_handle(handle text)
RETURNS boolean AS $$
BEGIN
  RETURN handle ~ '^[a-zA-Z0-9_-]{3,30}$';
END;
$$ LANGUAGE plpgsql;

-- Create handle verification function with record return type
CREATE OR REPLACE FUNCTION verify_user_handle(
  user_id uuid,
  new_handle text,
  OUT success boolean,
  OUT error text,
  OUT handle text
) AS $$
BEGIN
  -- Validate handle format
  IF NOT validate_handle(new_handle) THEN
    success := false;
    error := 'Invalid handle format. Use 3-30 characters, letters, numbers, underscore, or hyphen.';
    RETURN;
  END IF;

  -- Check if handle is already taken
  IF EXISTS (
    SELECT 1 FROM user_roles 
    WHERE handle = new_handle 
    AND user_id != verify_user_handle.user_id
  ) THEN
    success := false;
    error := 'Handle already taken';
    RETURN;
  END IF;

  -- Update handle
  UPDATE user_roles
  SET 
    handle = new_handle,
    updated_at = now()
  WHERE user_id = verify_user_handle.user_id;

  IF NOT FOUND THEN
    success := false;
    error := 'User not found';
    RETURN;
  END IF;

  success := true;
  error := null;
  handle := new_handle;
END;
$$ LANGUAGE plpgsql;

-- Create new user trigger function
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_handle text;
BEGIN
  -- Generate default handle from email
  default_handle := split_part(new.email, '@', 1);
  
  -- Ensure handle meets requirements
  IF NOT validate_handle(default_handle) THEN
    default_handle := 'user' || substr(gen_random_uuid()::text, 1, 8);
  END IF;
  
  -- Add number suffix if handle exists
  WHILE EXISTS (SELECT 1 FROM user_roles WHERE handle = default_handle) LOOP
    default_handle := default_handle || substr(gen_random_uuid()::text, 1, 4);
  END LOOP;

  INSERT INTO user_roles (
    user_id,
    role,
    email_verified,
    handle,
    created_at,
    updated_at
  )
  VALUES (
    new.id,
    'child',
    false,
    default_handle,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create new trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Update mock data with handles
UPDATE user_roles
SET handle = CASE
  WHEN user_id = '11111111-1111-1111-1111-111111111111' THEN 'player1'
  WHEN user_id = '22222222-2222-2222-2222-222222222222' THEN 'player2'
  WHEN user_id = '33333333-3333-3333-3333-333333333333' THEN 'player3'
  WHEN user_id = '44444444-4444-4444-4444-444444444444' THEN 'player4'
  WHEN user_id = '55555555-5555-5555-5555-555555555555' THEN 'player5'
  ELSE 'user' || substr(gen_random_uuid()::text, 1, 8)
END
WHERE handle IS NULL;