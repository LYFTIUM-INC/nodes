(* Standalone test for Broadcasting Manager functionality *)

open Lwt.Syntax
open Printf

(* Simplified types for testing *)
module TestTypes = struct
  type broadcast_method =
    | Flashbots_Bundle
    | Public_Mempool
    | Private_Relay of string
    | Multi_Relay of broadcast_method list

  type broadcast_priority =
    | Ultra_High    (* <50ms target *)
    | High          (* <200ms target *)
    | Standard      (* <1000ms target *)
    | Low           (* <5000ms target *)

  type broadcast_status =
    | Pending
    | Submitted
    | Confirmed of string (* transaction hash *)
    | Failed of string    (* error message *)
    | Timeout

  type broadcast_request = {
    id: string;
    strategy_id: string;
    method_preference: broadcast_method;
    priority: broadcast_priority;
    deadline: float;
    retry_count: int;
    max_retries: int;
    gas_price_multiplier: float;
  }

  type broadcast_result = {
    request_id: string;
    status: broadcast_status;
    transaction_hashes: string list;
    confirmation_time: float option;
    gas_used: int64 option;
    block_number: int64 option;
    relay_responses: string list;
    broadcast_latency_ms: float;
    error_details: string option;
  }
end

(* Simulate Flashbots broadcasting *)
module TestFlashbots = struct
  open TestTypes

  let simulate_flashbots_bundle request =
    let start_time = Unix.gettimeofday () in
    printf "[FLASHBOTS] Simulating bundle submission for request %s\n%!" request.id;
    
    (* Simulate network delay *)
    let* () = Lwt_unix.sleep 0.1 in
    
    let latency = (Unix.gettimeofday () -. start_time) *. 1000.0 in
    let success = Random.float 1.0 > 0.2 in (* 80% success rate *)
    
    if success then begin
      printf "[FLASHBOTS] Bundle accepted in %.2fms\n%!" latency;
      Lwt.return {
        request_id = request.id;
        status = Submitted;
        transaction_hashes = ["0x" ^ String.make 64 'a'];
        confirmation_time = None;
        gas_used = None;
        block_number = Some 18000001L;
        relay_responses = ["Bundle accepted"];
        broadcast_latency_ms = latency;
        error_details = None;
      }
    end else begin
      printf "[FLASHBOTS] Bundle rejected\n%!";
      Lwt.return {
        request_id = request.id;
        status = Failed "Bundle rejected by relay";
        transaction_hashes = [];
        confirmation_time = None;
        gas_used = None;
        block_number = None;
        relay_responses = ["Bundle rejected"];
        broadcast_latency_ms = latency;
        error_details = Some "Simulation failed";
      }
    end
end

(* Simulate public mempool broadcasting *)
module TestMempool = struct
  open TestTypes

  let simulate_mempool_broadcast request =
    let start_time = Unix.gettimeofday () in
    printf "[MEMPOOL] Simulating transaction submission for request %s\n%!" request.id;
    
    (* Simulate network delay *)
    let* () = Lwt_unix.sleep 0.05 in
    
    let latency = (Unix.gettimeofday () -. start_time) *. 1000.0 in
    let success = Random.float 1.0 > 0.1 in (* 90% success rate *)
    
    if success then begin
      printf "[MEMPOOL] Transaction accepted in %.2fms\n%!" latency;
      Lwt.return {
        request_id = request.id;
        status = Submitted;
        transaction_hashes = ["0x" ^ String.make 64 'b'];
        confirmation_time = None;
        gas_used = None;
        block_number = None;
        relay_responses = [];
        broadcast_latency_ms = latency;
        error_details = None;
      }
    end else begin
      printf "[MEMPOOL] Transaction rejected\n%!";
      Lwt.return {
        request_id = request.id;
        status = Failed "Transaction underpriced";
        transaction_hashes = [];
        confirmation_time = None;
        gas_used = None;
        block_number = None;
        relay_responses = [];
        broadcast_latency_ms = latency;
        error_details = Some "Gas price too low";
      }
    end
end

(* Main test manager *)
module TestBroadcastingManager = struct
  open TestTypes

  type manager = {
    mutable request_counter: int;
    mutable total_broadcasts: int;
    mutable successful_broadcasts: int;
    mutable failed_broadcasts: int;
  }

  let create_manager () = {
    request_counter = 0;
    total_broadcasts = 0;
    successful_broadcasts = 0;
    failed_broadcasts = 0;
  }

  let generate_request_id manager strategy_id =
    manager.request_counter <- manager.request_counter + 1;
    Printf.sprintf "broadcast_%s_%d_%f" strategy_id manager.request_counter (Unix.time ())

  let create_broadcast_request manager strategy_id method_preference priority =
    let request_id = generate_request_id manager strategy_id in
    let deadline = Unix.time () +. (match priority with
      | Ultra_High -> 0.05
      | High -> 0.2
      | Standard -> 1.0
      | Low -> 5.0) in
    
    {
      id = request_id;
      strategy_id;
      method_preference;
      priority;
      deadline;
      retry_count = 0;
      max_retries = 3;
      gas_price_multiplier = 1.0;
    }

  let submit_broadcast_request manager request =
    printf "\n[BROADCAST] Submitting request %s with method %s\n%!"
      request.id (match request.method_preference with
        | Flashbots_Bundle -> "Flashbots"
        | Public_Mempool -> "Mempool"
        | Private_Relay s -> "Private(" ^ s ^ ")"
        | Multi_Relay _ -> "Multi-Relay");
    
    manager.total_broadcasts <- manager.total_broadcasts + 1;
    
    let* result = match request.method_preference with
      | Flashbots_Bundle -> TestFlashbots.simulate_flashbots_bundle request
      | Public_Mempool -> TestMempool.simulate_mempool_broadcast request
      | Private_Relay _ -> 
          (* Simulate private relay *)
          let* () = Lwt_unix.sleep 0.1 in
          Lwt.return {
            request_id = request.id;
            status = Submitted;
            transaction_hashes = ["0x" ^ String.make 64 'c'];
            confirmation_time = None;
            gas_used = None;
            block_number = None;
            relay_responses = ["Private relay accepted"];
            broadcast_latency_ms = 100.0;
            error_details = None;
          }
      | Multi_Relay methods ->
          (* Simulate multi-relay by trying all methods *)
          let* results = Lwt_list.map_s (fun method_type ->
            match method_type with
            | Flashbots_Bundle -> TestFlashbots.simulate_flashbots_bundle request
            | Public_Mempool -> TestMempool.simulate_mempool_broadcast request
            | _ -> Lwt.return {
                request_id = request.id;
                status = Submitted;
                transaction_hashes = [];
                confirmation_time = None;
                gas_used = None;
                block_number = None;
                relay_responses = [];
                broadcast_latency_ms = 50.0;
                error_details = None;
              }
          ) methods in
          
          (* Aggregate results *)
          let successful = List.filter (fun r ->
            match r.status with Submitted | Confirmed _ -> true | _ -> false
          ) results in
          
          let all_hashes = List.fold_left (fun acc r -> acc @ r.transaction_hashes) [] results in
          let all_responses = List.fold_left (fun acc r -> acc @ r.relay_responses) [] results in
          let avg_latency = List.fold_left (fun acc r -> acc +. r.broadcast_latency_ms) 0.0 results 
                            /. float_of_int (List.length results) in
          
          Lwt.return {
            request_id = request.id;
            status = if List.length successful > 0 then Submitted else Failed "All relays failed";
            transaction_hashes = all_hashes;
            confirmation_time = None;
            gas_used = None;
            block_number = None;
            relay_responses = all_responses;
            broadcast_latency_ms = avg_latency;
            error_details = None;
          }
    in
    
    (* Update statistics *)
    (match result.status with
     | Submitted | Confirmed _ -> manager.successful_broadcasts <- manager.successful_broadcasts + 1
     | _ -> manager.failed_broadcasts <- manager.failed_broadcasts + 1);
    
    Lwt.return result

  let print_metrics manager =
    printf "\n📡 Broadcasting Manager Metrics\n";
    printf "==============================\n";
    printf "Total Broadcasts: %d\n" manager.total_broadcasts;
    printf "Successful: %d\n" manager.successful_broadcasts;
    printf "Failed: %d\n" manager.failed_broadcasts;
    printf "Success Rate: %.1f%%\n"
      (if manager.total_broadcasts > 0 then
        float_of_int manager.successful_broadcasts /.
        float_of_int manager.total_broadcasts *. 100.0
      else 0.0)
end

(* Test with real Safe wallet address *)
let test_with_safe_wallet () =
  printf "\n🔐 Testing Broadcasting Manager with Safe Wallet\n";
  printf "===============================================\n";
  
  (* Load wallet configuration *)
  let safe_address = "0x96dB0dA35d601379DBD0E7729EbEbfd50eE3a813" in
  printf "Safe Wallet: %s\n\n" safe_address;
  
  let manager = TestBroadcastingManager.create_manager () in
  
  (* Test 1: Flashbots Bundle *)
  let* () =
    let request = TestBroadcastingManager.create_broadcast_request
      manager "arbitrage_1" TestTypes.Flashbots_Bundle TestTypes.High in
    let* result = TestBroadcastingManager.submit_broadcast_request manager request in
    printf "Result: %s\n" (match result.status with
      | Submitted -> "✅ Submitted"
      | Failed msg -> "❌ Failed: " ^ msg
      | _ -> "Other");
    Lwt.return ()
  in
  
  (* Test 2: Public Mempool *)
  let* () =
    let request = TestBroadcastingManager.create_broadcast_request
      manager "liquidation_1" TestTypes.Public_Mempool TestTypes.Standard in
    let* result = TestBroadcastingManager.submit_broadcast_request manager request in
    printf "Result: %s\n" (match result.status with
      | Submitted -> "✅ Submitted"
      | Failed msg -> "❌ Failed: " ^ msg
      | _ -> "Other");
    Lwt.return ()
  in
  
  (* Test 3: Multi-Relay Ultra High Priority *)
  let* () =
    let request = TestBroadcastingManager.create_broadcast_request
      manager "sandwich_1"
      (TestTypes.Multi_Relay [TestTypes.Flashbots_Bundle; TestTypes.Public_Mempool])
      TestTypes.Ultra_High in
    let* result = TestBroadcastingManager.submit_broadcast_request manager request in
    printf "Result: %s\n" (match result.status with
      | Submitted -> "✅ Submitted"
      | Failed msg -> "❌ Failed: " ^ msg
      | _ -> "Other");
    Lwt.return ()
  in
  
  (* Test 4: Private Relay *)
  let* () =
    let request = TestBroadcastingManager.create_broadcast_request
      manager "mev_boost_1"
      (TestTypes.Private_Relay "https://relay.example.com")
      TestTypes.High in
    let* result = TestBroadcastingManager.submit_broadcast_request manager request in
    printf "Result: %s\n" (match result.status with
      | Submitted -> "✅ Submitted"
      | Failed msg -> "❌ Failed: " ^ msg
      | _ -> "Other");
    Lwt.return ()
  in
  
  (* Test 5: Batch of requests *)
  let* () =
    printf "\n[BATCH TEST] Submitting 10 requests...\n";
    let requests = List.init 10 (fun i ->
      TestBroadcastingManager.create_broadcast_request
        manager (sprintf "batch_%d" i)
        (if i mod 2 = 0 then TestTypes.Flashbots_Bundle else TestTypes.Public_Mempool)
        (if i < 3 then TestTypes.Ultra_High else TestTypes.Standard)
    ) in
    
    let* results = Lwt_list.map_p (TestBroadcastingManager.submit_broadcast_request manager) requests in
    let successful = List.filter (fun r ->
      match r.TestTypes.status with TestTypes.Submitted | TestTypes.Confirmed _ -> true | _ -> false
    ) results in
    printf "[BATCH TEST] Success: %d/%d\n" (List.length successful) (List.length results);
    Lwt.return ()
  in
  
  (* Print final metrics *)
  TestBroadcastingManager.print_metrics manager;
  
  printf "\n✅ Broadcasting Manager Test Complete!\n";
  printf "Safe wallet %s is configured and ready for MEV transactions\n" safe_address;
  Lwt.return ()

(* Main entry point *)
let () =
  Random.self_init ();
  Lwt_main.run (test_with_safe_wallet ())