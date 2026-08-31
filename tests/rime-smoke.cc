#include <rime_api.h>

#include <cstring>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
  if (argc != 3) {
    std::cerr << "usage: rime-smoke <shared-data-dir> <user-data-dir>\n";
    return 2;
  }

  RimeApi* api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.app_name = "rime.ready.smoke";
  traits.distribution_name = "rime-ready smoke test";
  traits.distribution_code_name = "rime-ready-smoke";
  traits.distribution_version = "1";
  traits.log_dir = "";
  api->setup(&traits);
  api->initialize(&traits);

  RimeSessionId session = api->create_session();
  if (!session || !api->select_schema(session, "rime_ice") ||
      !api->simulate_key_sequence(session, "nihao")) {
    std::cerr << "failed to create a Rime Ice session or process nihao\n";
    api->finalize();
    return 1;
  }

  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(session, &context)) {
    std::cerr << "failed to read Rime context\n";
    api->destroy_session(session);
    api->finalize();
    return 1;
  }

  int candidate_index = -1;
  for (int i = 0; i < context.menu.num_candidates; ++i) {
    const char* text = context.menu.candidates[i].text;
    std::cout << "candidate[" << i << "]=" << (text ? text : "") << "\n";
    if (text && std::strcmp(text, "你好") == 0) candidate_index = i;
  }
  api->free_context(&context);

  if (candidate_index < 0 || !api->select_candidate(session, candidate_index)) {
    std::cerr << "candidate 你好 was not generated or selected\n";
    api->destroy_session(session);
    api->finalize();
    return 1;
  }

  RIME_STRUCT(RimeCommit, commit);
  if (!api->get_commit(session, &commit) || !commit.text ||
      std::strcmp(commit.text, "你好") != 0) {
    std::cerr << "expected committed text: 你好\n";
    api->destroy_session(session);
    api->finalize();
    return 1;
  }
  std::cout << "commit=" << commit.text << "\n";
  api->free_commit(&commit);
  api->destroy_session(session);
  api->finalize();
  return 0;
}
